import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';
import 'package:local_bluey/services/native_control.dart';
import 'package:local_bluey/services/tool_executor.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/workflows/host_ax_postcondition_reader.dart';
import 'package:local_bluey/workflows/postcondition_verifier.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _Host extends MacHostControl {
  bool trusted = true;
  String label = 'Ready';
  String targets = 'button';
  int snapshots = 0;
  int resolutions = 0;
  void Function()? onSnapshot;

  @override
  Future<bool> isTrusted() async => trusted;

  @override
  Future<ScreenSnapshot> snapshot() async {
    snapshots++;
    onSnapshot?.call();
    return ScreenSnapshot(
      jpeg: Uint8List(0),
      targets: targets,
      width: 1,
      height: 1,
    );
  }

  @override
  Future<ResolvedTarget> resolveTarget(String id) async {
    resolutions++;
    return ResolvedTarget(0, 0, label);
  }
}

class _Delegate implements WorkflowHost {
  int executions = 0;

  @override
  Future<bool> approve(WorkflowStep step) async => true;

  @override
  Future<void> execute(WorkflowStep step) async {
    executions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

void main() {
  final expected = Postcondition.parse('ax:button=Done');

  test('live AX mismatch cannot certify attempted workflow action', () async {
    final host = _Host();
    final delegate = _Delegate();
    final definition = WorkflowDefinition.fromJson({
      'version': 1,
      'id': 'ax-test',
      'trigger': 'manual',
      'steps': [
        {'type': 'hostAction', 'target': 'button'},
      ],
    });
    final execution = WorkflowExecution(
      definition,
      withHostAxVerification(
        delegate: delegate,
        control: host,
        gate: SafetyGate(),
        hasUserConsent: () => true,
        postconditions: [expected],
        timeout: const Duration(seconds: 1),
      ),
      deadline: const Duration(seconds: 2),
    );

    expect(await execution.run(), WorkflowStatus.failed);
    expect(delegate.executions, 1);
    expect(host.snapshots, 1);
    expect(host.resolutions, 1);
  });

  test('live AX reader requires explicit consent and trusted host', () async {
    final host = _Host()..label = 'Done';
    var consent = false;
    final reader = HostAxPostconditionReader(
      control: host,
      gate: SafetyGate(),
      hasUserConsent: () => consent,
    );
    final verifier = PostconditionVerifier(reader);
    expect(
      await verifier.verify([expected], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
    expect(host.snapshots, 0);

    consent = true;
    host.trusted = false;
    expect(
      await verifier.verify([expected], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
    expect(host.snapshots, 0);
  });

  test('kill and reset during AX observation cannot certify success', () async {
    final gate = SafetyGate();
    final host = _Host()..label = 'Done';
    host.onSnapshot = () {
      gate.kill();
      gate.reset();
    };
    final verifier = PostconditionVerifier(
      HostAxPostconditionReader(
        control: host,
        gate: gate,
        hasUserConsent: () => true,
      ),
    );
    expect(
      await verifier.verify([expected], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
    expect(host.resolutions, 0);
  });
}
