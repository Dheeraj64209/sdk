class CallActions {
  const CallActions({
    this.canAnswer = false,
    this.canReject = false,
    this.canHangup = false,
    this.canMute = false,
    this.canSendDtmf = false,
  });

  final bool canAnswer;
  final bool canReject;
  final bool canHangup;
  final bool canMute;
  final bool canSendDtmf;
}
