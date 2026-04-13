import 'package:flutter/material.dart';

import '../../integration/dependency_injection.dart';
import '../viewmodels/call_view_model.dart';
import '../viewmodels/sdk_view_model.dart';
import 'active_call_screen.dart';
import 'incoming_call_screen.dart';

/// Second screen of the demo app.
///
/// It lets the user enter a phone number, place a call, react to incoming
/// calls, and transition into the dedicated call screen.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  late final CallViewModel _callViewModel;
  late final TextEditingController _numberController;
  bool _initialized = false;
  bool _incomingDialogVisible = false;
  bool _callScreenVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    final SdkViewModel sdkViewModel = DependencyInjection.of(
      context,
    ).sdkViewModel;
    _callViewModel = CallViewModel(sdkViewModel.client);
    _numberController = TextEditingController();
    _callViewModel.addListener(_syncTextField);
    _initialized = true;
  }

  @override
  void dispose() {
    _callViewModel.removeListener(_syncTextField);
    _callViewModel.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SdkViewModel sdkViewModel = DependencyInjection.of(
      context,
    ).sdkViewModel;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[sdkViewModel, _callViewModel]),
      builder: (BuildContext context, _) {
        _handleCallUiTransitions();

        return Scaffold(
          backgroundColor: const Color(0xFFF3F5F8),
          appBar: AppBar(
            title: const Text('Dialer'),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  await sdkViewModel.disconnect();
                  if (!mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('Logout'),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    _InfoPanel(
                      title: 'SDK Connection',
                      body: sdkViewModel.connectionEvent == null
                          ? 'Disconnected'
                          : '${sdkViewModel.connectionEvent!.connectionState.name} / '
                              '${sdkViewModel.connectionEvent!.registrationState.name}',
                    ),
                    const SizedBox(height: 16),
                    _InfoPanel(
                      title: 'Call Status',
                      body: _callViewModel.latestCallEvent == null
                          ? 'No active call'
                          : '${_callViewModel.latestCallEvent!.state.name}'
                              '${_callViewModel.activeCallId == null ? '' : ' | ${_callViewModel.activeCallId}'}',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _numberController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Enter Number',
                        hintText: 'Destination number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dialpad_rounded),
                      ),
                      onChanged: _callViewModel.setDestination,
                    ),
                    const SizedBox(height: 20),
                    _DialPad(
                      onKeyTap: _callViewModel.appendDigit,
                      onBackspace: _callViewModel.backspace,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _callViewModel.isBusy || !sdkViewModel.isConnected
                                ? null
                                : _callViewModel.makeCall,
                        icon: _callViewModel.isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.call),
                        label: const Text('Call'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _callViewModel.canHangup
                            ? _callViewModel.hangup
                            : null,
                        icon: const Icon(Icons.call_end),
                        label: const Text('End Call'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                      ),
                    ),
                    if (_callViewModel.errorMessage != null &&
                        _callViewModel.errorMessage!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        _callViewModel.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncTextField() {
    if (_numberController.text == _callViewModel.enteredNumber) {
      return;
    }
    _numberController.value = TextEditingValue(
      text: _callViewModel.enteredNumber,
      selection: TextSelection.collapsed(
        offset: _callViewModel.enteredNumber.length,
      ),
    );
  }

  void _handleCallUiTransitions() {
    final bool shouldShowIncomingPopup = _callViewModel.isIncomingRinging;
    final bool shouldShowCallScreen =
        _callViewModel.isCalling && !_callViewModel.isIncomingRinging;

    if (shouldShowIncomingPopup && !_incomingDialogVisible) {
      _incomingDialogVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return IncomingCallScreen(
              caller: _callViewModel.remoteIdentity,
              onAnswer: () async {
                Navigator.of(dialogContext).pop();
                await _callViewModel.acceptIncomingCall();
              },
              onReject: () async {
                Navigator.of(dialogContext).pop();
                await _callViewModel.rejectIncomingCall();
              },
            );
          },
        );
        _incomingDialogVisible = false;
      });
    }

    if (_incomingDialogVisible && !shouldShowIncomingPopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        Navigator.of(context, rootNavigator: true).maybePop();
      });
    }

    if (shouldShowCallScreen && !_callScreenVisible) {
      _callScreenVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnimatedBuilder(
              animation: _callViewModel,
              builder: (BuildContext context, __) {
                return ActiveCallScreen(
                  remoteIdentity: _callViewModel.remoteIdentity,
                  callState:
                      _callViewModel.latestCallEvent?.state.name ?? 'Call',
                  isMuted: _callViewModel.isMuted,
                  onToggleMute: _callViewModel.toggleMute,
                  onHangup: () async {
                    await _callViewModel.hangup();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
            fullscreenDialog: true,
          ),
        );
        _callScreenVisible = false;
      });
    }

    if (_callScreenVisible && !shouldShowCallScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).maybePop();
      });
    }
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E7ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DialPad extends StatelessWidget {
  const _DialPad({required this.onKeyTap, required this.onBackspace});

  final ValueChanged<String> onKeyTap;
  final VoidCallback onBackspace;

  static const List<String> _keys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '*',
    '0',
    '#',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemCount: _keys.length,
          itemBuilder: (BuildContext context, int index) {
            final String key = _keys[index];
            return FilledButton.tonal(
              onPressed: () => onKeyTap(key),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                key,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton.filledTonal(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined),
          ),
        ),
      ],
    );
  }
}
