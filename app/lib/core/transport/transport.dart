/// Transporte abstrato: tudo acima disto ignora se o link e USB ou BLE.
library;

/// Um link bidirecional de mensagens SysEx.
///
/// O transporte entrega bytes crus (incluindo `F0`/`F7`) no fluxo de entrada.
/// Sobre BLE proprietario o payload trafega sem envelope; quem implementa o
/// transporte e responsavel por adaptar.
abstract class TankTransport {
  /// Nome legivel do dispositivo, para exibicao.
  String get name;

  /// Abre a conexao. Deve lancar [TransportException] se falhar.
  Future<void> open();

  /// Envia um frame SysEx completo.
  Future<void> send(List<int> frame);

  /// Fluxo de frames recebidos.
  Stream<List<int>> get incoming;

  /// Fecha a conexao.
  Future<void> close();
}

/// Erro de transporte.
class TransportException implements Exception {
  TransportException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'TransportException: $message${cause == null ? '' : ' ($cause)'}';
}
