class CallStats {
  const CallStats({
    this.jitterMs,
    this.rttMs,
    this.packetLossPercent,
  });

  final double? jitterMs;
  final double? rttMs;
  final double? packetLossPercent;
}
