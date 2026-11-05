import 'dart:async';

import '../model/model_flash.dart';
import '../model/preset.dart';
import '../protocol/messages.dart';
import '../transport/transport.dart';

/// Erro de leitura.
class ReadException implements Exception {
  ReadException(this.message);

  final String message;

  @override
  String toString() => 'ReadException: $message';
}

/// Erro de escrita.
class WriteException implements Exception {
  WriteException(this.message);

  final String message;

  @override
  String toString() => 'WriteException: $message';
}

/// A gravacao foi aceita mas a releitura nao confere.
class FlashWriteException extends WriteException {
  FlashWriteException(super.message);
}

/// Uma resposta recebida do dispositivo.
class _Response {
  bool accepts(List<int> raw) => true;

  /// `00 59 00 01 00 00 00 FF` — aceito.
  ///
  /// O byte 3 vale `01` tanto no ACK quanto no NAK; o que distingue e o byte 6
  /// (`00` aceito, `01` recusado).
  static bool isAck(List<int> raw) =>
      raw.length >= 8 &&
      raw[0] == 0x00 &&
      raw[1] == 0x59 &&
      raw[2] == 0x00 &&
      raw[3] == 0x01 &&
      raw[6] == 0x00;

  static bool isNak(List<int> raw) =>
      raw.length >= 8 &&
      raw[0] == 0x00 &&
      raw[1] == 0x59 &&
      raw[2] == 0x00 &&
      raw[3] == 0x01 &&
      raw[6] != 0x00;

  static bool isData(List<int> raw) =>
      raw.length >= 16 && raw[0] == 0x00 && raw[1] == 0x59 && raw[2] == 0x23;
}

/// Cliente de alto nivel da Tank Mini.
///
/// Traduz chamadas de negocio em mensagens do protocolo e valida as respostas.
/// Nao conhece Flutter nem MIDI diretamente: recebe um [TankTransport].
class TankDevice {
  TankDevice(
    this.transport, {
    this.readTimeout = const Duration(seconds: 3),
    this.maxAttempts = 3,
  });

  final TankTransport transport;
  final Duration readTimeout;

  /// Quantas vezes uma requisicao sem resposta e repetida antes de desistir.
  final int maxAttempts;

  StreamSubscription<List<int>>? _subscription;
  Completer<List<int>>? _waiter;
  String _identity = '';
  bool _open = false;

  /// Fila de conversas: o protocolo nao tem correlacao de ID, entao so pode
  /// existir uma requisicao em voo por vez.
  ///
  /// Sem a fila, uma consulta periodica concorrendo com uma edicao do usuario
  /// derrubava a segunda com "Requisicao anterior ainda em andamento" — e na
  /// interface isso aparecia como falha de conexao.
  Future<void> _queue = Future<void>.value();

  /// Quadros que chegaram depois de um timeout.
  ///
  /// Uma resposta atrasada seria entregue ao proximo [waiter] e corromperia a
  /// leitura seguinte. Em vez de tentar casar respostas (o protocolo nao tem
  /// ID), ao estourar o tempo a fila e parada por um instante e o que chegar
  /// nesse intervalo e descartado.
  bool _draining = false;

  final StreamController<void> _lost = StreamController<void>.broadcast();

  String get identity => _identity;
  bool get isOpen => _open;

  /// Emite quando o transporte cai (BLE desconectado, porta removida).
  Stream<void> get lost => _lost.stream;

  TransportException? get lostReason => _lostError;

  Future<String> connect() async {
    // O BLE precisa avisar antes: se o sistema derrubar o link, a sessao
    // termina na hora em vez de cada requisicao morrer no timeout.
    if (transport case final BleDisconnectHook hook) {
      hook.onDisconnected = () => markLost('Conexao BLE encerrada');
    }
    await transport.open();
    _subscription = transport.incoming.listen(_onFrame);
    _open = true;
    _identity = await identify();
    return _identity;
  }

  /// Avisa que a conexao caiu do lado do transporte.
  ///
  /// Chamado pelo BLE quando o sistema reporta desconexao: a fila e acordada com
  /// erro em vez de deixar a proxima requisicao esperar o timeout inteiro.
  void markLost(String reason) {
    if (!_open) return;
    _open = false;
    final error = TransportException(reason);
    _lostError = error;
    _waiter?.completeError(error);
    _waiter = null;
    if (!_lost.isClosed) _lost.add(null);
  }

  /// Erro que derrubou a sessao, repetido nas requisicoes seguintes.
  ///
  /// Guardar a causa evita que uma queda de link apareca como "nao conectado"
  /// generico: o usuario ve o motivo real.
  TransportException? _lostError;

  Future<void> disconnect() async {
    _open = false;
    _waiter?.completeError(TransportException('Conexao encerrada'));
    _waiter = null;
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
    await _lost.close();
  }

  void _onFrame(List<int> frame) {
    if (_draining) return;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(frame);
    }
  }

  /// Executa [action] com exclusividade, respeitando a ordem de chegada.
  ///
  /// A fila nunca fica presa: se uma acao falhar, a proxima ainda roda.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final previous = _queue;
    final completer = Completer<void>();
    _queue = completer.future;
    return previous
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => action())
        .whenComplete(completer.complete);
  }

  /// Envia [frame] e devolve a proxima resposta.
  ///
  /// Repete a requisicao quando o pedal nao responde: no BLE uma notificacao
  /// perdida e comum e a repeticao resolve sem incomodar o usuario.
  Future<List<int>> _exchange(List<int> frame, {Duration? timeout}) {
    return _serialize(() async {
      Object lastError = _lostError ?? StateError('Dispositivo nao conectado');
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (!_open) {
          throw _lostError ??
              (lastError is TransportException
                  ? lastError
                  : StateError('Dispositivo nao conectado'));
        }
        try {
          return await _attempt(frame, timeout ?? readTimeout);
        } on TimeoutException catch (error) {
          lastError = TransportException(
            'Sem resposta do dispositivo apos $attempt tentativa(s)',
            error,
          );
          if (attempt < maxAttempts) await _drainStale();
        }
      }
      throw lastError;
    });
  }

  Future<List<int>> _attempt(List<int> frame, Duration timeout) async {
    final waiter = Completer<List<int>>();
    _waiter = waiter;
    try {
      await transport.send(frame);
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      throw TimeoutException('Sem resposta do dispositivo', timeout);
    } finally {
      _waiter = null;
    }
  }

  /// Descarta o que ainda estiver a caminho depois de um timeout.
  Future<void> _drainStale() async {
    _draining = true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    _draining = false;
  }

  /// Identificacao do aparelho.
  Future<String> identify() async {
    final raw = await _exchange(
      identifyRequest(),
      timeout: const Duration(seconds: 2),
    );
    final body = raw.length > 4
        ? raw.sublist(4, raw.length - 1)
        : const <int>[];
    final text = StringBuffer();
    for (final byte in body) {
      if (byte >= 0x20 && byte < 0x7F) {
        text.writeCharCode(byte);
      } else if (byte == 0x00) {
        break;
      }
    }
    final value = text.toString().trim();
    return value.isEmpty ? 'TANK MINI' : value;
  }

  // --- leitura ---

  /// Le [length] bytes de [address] numa unica requisicao (ate [maxRead]).
  Future<List<int>> readBytes(
    int address,
    int length, {
    int area = Area.presets,
    Duration? timeout,
  }) async {
    if (length <= 0 || length > maxRead) {
      throw ArgumentError('Leitura deve ter entre 1 e $maxRead bytes');
    }
    final raw = await _exchange(
      readRequest(address, length, area: area),
      timeout: timeout,
    );
    if (_Response.isNak(raw)) {
      throw ReadException('Endereco $address ilegivel');
    }
    if (!_Response.isData(raw)) {
      throw ReadException('Resposta inesperada de leitura: ${_hex(raw)}');
    }
    final payload = raw.sublist(14, raw.length - 1);
    if (payload.length != length) {
      throw ReadException(
        'Tamanho divergente: pedido $length, recebido ${payload.length}',
      );
    }
    // A resposta ecoa o endereco. Conferir evita atribuir a um chunk o
    // conteudo de outro quando uma resposta atrasada chega fora de ordem.
    final echoed = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
    if (echoed != address) {
      throw ReadException(
        'Resposta do endereco ${_hex32(echoed)} para pedido em '
        '${_hex32(address)}',
      );
    }
    return payload;
  }

  /// Le um bloco maior, fatiando em requisicoes de ate [maxRead] bytes.
  Future<List<int>> readBlock(
    int address,
    int length, {
    int area = Area.presets,
    Duration? timeout,
  }) async {
    final out = <int>[];
    while (out.length < length) {
      final remaining = length - out.length;
      final chunk = remaining > maxRead ? maxRead : remaining;
      out.addAll(
        await readBytes(
          address + out.length,
          chunk,
          area: area,
          timeout: timeout,
        ),
      );
    }
    return out;
  }

  /// Le o preset ativo da RAM.
  Future<Preset> readActive() async =>
      Preset.fromBytes(await readBytes(ramAddress, presetSize));

  /// Le um slot da flash.
  Future<Preset> readSlot(int slot) async =>
      Preset.fromBytes(await readBytes(slot * presetSize, presetSize));

  // --- escrita ---

  Future<void> _write(
    List<int> payload, {
    required int address,
    required int area,
    required bool commit,
  }) async {
    final raw = await _exchange(writeRequest(address, payload, area: area));
    if (_Response.isNak(raw)) {
      throw WriteException('Escrita rejeitada em $address');
    }
    if (!_Response.isAck(raw)) {
      throw WriteException('Resposta inesperada de escrita: ${_hex(raw)}');
    }
    if (commit) {
      final ack = await _exchange(commitRequest());
      if (!_Response.isAck(ack)) {
        throw WriteException('Commit nao confirmado: ${_hex(ack)}');
      }
    }
  }

  /// Grava um preset direto na flash.
  Future<void> saveSlot(int slot, Preset preset) => _write(
    preset.bytes,
    address: slot * presetSize,
    area: Area.presets,
    commit: true,
  );

  /// Seleciona o slot e, se [expected] for informado, espera a RAM convergir.
  Future<int> selectSlot(
    int slot, {
    Preset? expected,
    Duration? timeout,
  }) async {
    final raw = await _exchange(selectRequest(slot));
    if (!_Response.isAck(raw)) {
      throw WriteException('Selecao rejeitada: ${_hex(raw)}');
    }
    if (expected == null) {
      return 0;
    }
    final deadline = DateTime.now().add(timeout ?? const Duration(seconds: 3));
    var reads = 0;
    while (DateTime.now().isBefore(deadline)) {
      reads++;
      if (await readActive() == expected) {
        return reads;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    throw TimeoutException(
      'Selecao nao convergiu; o pedal pode estar em outro estado',
    );
  }

  /// Troca dois presets de slot, validando o resultado.
  Future<void> swapSlots(int a, int b) async {
    final first = await readSlot(a);
    final second = await readSlot(b);
    await saveSlot(b, first);
    await saveSlot(a, second);
    if (await readSlot(a) != second || await readSlot(b) != first) {
      throw WriteException('Swap entre $a e $b nao confirmou');
    }
  }

  // --- tempo real ---

  Future<void> setBlockEnabled(Block block, bool enabled) async {
    final raw = await _exchange(
      toggleRequest(block.toggleAddress, enabled ? 1 : 0),
    );
    if (!_Response.isAck(raw)) {
      throw WriteException('Toggle rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setBlockModel(Block block, int model) async {
    final raw = await _exchange(toggleRequest(block.modelAddress, model));
    if (!_Response.isAck(raw)) {
      throw WriteException('Troca de modelo rejeitada: ${_hex(raw)}');
    }
  }

  Future<void> setParameter(int offset, int value) async {
    final raw = await _exchange(knobRequest(offset, value));
    if (!_Response.isAck(raw)) {
      throw WriteException('Parametro rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setVolume(int value) => setParameter(0, value);

  Future<void> setRouting(List<int> order) async {
    final raw = await _exchange(routingRequest(order));
    if (!_Response.isAck(raw)) {
      throw WriteException('Routing rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setBypass(bool enabled) async {
    final raw = await _exchange(bypassRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Bypass rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setLoopback(bool enabled) async {
    final raw = await _exchange(loopbackRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Loopback rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setTuner(bool enabled) async {
    final raw = await _exchange(tunerRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Afinador rejeitado: ${_hex(raw)}');
    }
  }

  /// Envia um buffer de modelo (AMP = 1, CAB = 2) e ativa o preview.
  Future<void> uploadModel(List<int> buffer, {required int previewKind}) async {
    for (var offset = 0; offset < buffer.length; offset += maxWrite) {
      final end = offset + maxWrite;
      final chunk = buffer.sublist(
        offset,
        end > buffer.length ? buffer.length : end,
      );
      await _write(chunk, address: offset, area: Area.model, commit: false);
    }
    final raw = await _exchange(previewModelRequest(kind: previewKind));
    if (!_Response.isAck(raw)) {
      throw WriteException('Preview de modelo rejeitado: ${_hex(raw)}');
    }
  }

  /// Grava um modelo de forma permanente na flash de modelos.
  ///
  /// O fluxo reproduz o "Restore Amp/Cab" do editor oficial: apaga os setores
  /// que o registro ocupa e escreve o registro em blocos de [maxWrite] bytes.
  /// **Nao ha commit**: a captura do editor nao envia nenhum, e enviar o
  /// commit de preset com `area 0x05` faz o pedal descartar a gravacao.
  ///
  /// Lanca [FlashWriteException] quando a releitura nao bate com o envio.
  Future<void> writeModelFlash(
    int address,
    List<int> record, {
    void Function(double progress)? onProgress,
  }) async {
    final sectors = eraseSectorsFor(address, record.length);
    final blocks = (record.length / maxWrite).ceil();
    final total = sectors.length + blocks + 1;
    var done = 0;

    for (final sector in sectors) {
      final raw = await _exchange(eraseSectorRequest(sector));
      if (!_Response.isAck(raw)) {
        throw WriteException('Apagamento de ${_hex32(sector)} recusado');
      }
      onProgress?.call(++done / total);
    }

    for (var offset = 0; offset < record.length; offset += maxWrite) {
      final end = offset + maxWrite;
      final chunk = record.sublist(
        offset,
        end > record.length ? record.length : end,
      );
      await _write(
        chunk,
        address: address + offset,
        area: Area.model,
        commit: false,
      );
      onProgress?.call(++done / total);
    }

    final check = await readBlock(address, record.length, area: Area.model);
    for (var i = 0; i < record.length; i++) {
      if (check[i] != record[i]) {
        throw FlashWriteException(
          'Verificacao falhou em ${_hex32(address + i)}: '
          'gravado ${check[i].toRadixString(16)}, '
          'esperado ${record[i].toRadixString(16)}',
        );
      }
    }
    onProgress?.call(1);
  }

  /// Le o registro de um modelo da flash (8192 para AMP, 4096 para CAB).
  Future<List<int>> readModelFlash(int address, int length) =>
      readBlock(address, length, area: Area.model);

  /// Le os nomes de AMP e CAB direto do pedal.
  ///
  /// Sao duas leituras: `0x90000000` para os AMPs e `0x80000000` para os CABs,
  /// 20 registros de 14 bytes cada. A tabela e **viva**: gravar um modelo na
  /// flash troca o nome na hora, sem precisar reiniciar (conferido no pedal em
  /// 2026-11-04).
  ///
  /// Pedir o mesmo bloco a partir de um offset devolve o conteudo espelhado com
  /// o primeiro byte alterado; por isso o endereco pedido e sempre o base.
  ///
  /// FX, MOD, DLY e REV nao tem tabela de nomes no pedal — varrendo
  /// `0x80000000`..`0xA0000000` so aparecem estas duas.
  Future<ModelNames> readModelNames() async {
    final amp = decodeNameTable(
      await readBlock(ampNameTableAddress, nameTableBytes, area: Area.model),
    );
    final cab = decodeNameTable(
      await readBlock(cabNameTableAddress, nameTableBytes, area: Area.model),
    );
    return ModelNames(amp: amp, cab: cab);
  }

  static String _hex32(int value) =>
      '0x${value.toRadixString(16).padLeft(8, '0')}';

  static String _hex(List<int> data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
