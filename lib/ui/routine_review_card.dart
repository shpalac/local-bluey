import 'package:flutter/material.dart';

import '../services/routines.dart';
import '../services/routine_proposal.dart';
import '../services/strings.dart';

/// Unwired review surface for an existing disabled legacy Routine.
/// Callbacks convey a choice only; no store, activation or execution here.
class RoutineReviewCard extends StatefulWidget {
  const RoutineReviewCard({
    super.key,
    required this.routine,
    required this.onAccept,
    required this.onDecline,
  });
  final Routine routine;
  final Future<void> Function(Routine) onAccept;
  final VoidCallback onDecline;
  @override
  State<RoutineReviewCard> createState() => _RoutineReviewCardState();
}

class _RoutineReviewCardState extends State<RoutineReviewCard> {
  bool _pending = false;
  bool _failed = false;
  bool _editing = false;
  String? _editedInstructions;

  Routine? get _proposal {
    if (!_editing || _editedInstructions == null) return widget.routine;
    try {
      return RoutineProposal.fromFields({
        'name': widget.routine.name,
        'trigger': widget.routine.trigger,
        'instructions': _editedInstructions,
      }).routine;
    } on RoutineProposalException {
      return null;
    }
  }

  Future<void> _accept() async {
    if (_pending || widget.routine.enabled) return;
    final proposal = _proposal;
    if (proposal == null) return;
    setState(() {
      _pending = true;
      _failed = false;
    });
    try {
      await widget.onAccept(proposal);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.routine.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            Strings.t(
              'Draft only. Nothing is enabled or run here.',
              'טיוטה בלבד. שום דבר לא מופעל או מבוצע כאן.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            Strings.t('Trigger', 'ביטוי הפעלה'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(widget.routine.trigger),
          const SizedBox(height: 8),
          Text(
            Strings.t('Proposed instructions', 'הוראות מוצעות'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(widget.routine.instructions),
          if (_editing && !widget.routine.enabled) ...[
            TextField(
              key: const ValueKey('workflow-draft-instructions'),
              decoration: InputDecoration(labelText: Strings.t('Edit instructions', 'עריכת הוראות')),
              onChanged: (value) => setState(() => _editedInstructions = value),
            ),
            Text(Strings.t('Before', 'לפני')),
            Text(widget.routine.instructions),
            Text(Strings.t('After', 'אחרי')),
            Text(_editedInstructions ?? widget.routine.instructions),
            if (_proposal == null)
              Text(Strings.t('Invalid draft fields', 'שדות טיוטה לא תקינים')),
          ],
          if (widget.routine.enabled)
            Text(
              Strings.t(
                'Only a disabled draft can be reviewed here.',
                'אפשר לבדוק כאן רק טיוטה לא פעילה.',
              ),
            ),
          if (_failed)
            Semantics(
              liveRegion: true,
              child: Text(
                Strings.t(
                  'Draft review failed. Try again.',
                  'בדיקת הטיוטה נכשלה. נסו שוב.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _pending || widget.routine.enabled || _proposal == null ? null : _accept,
                child: Text(
                  Strings.t('Accept disabled draft', 'אישור טיוטה לא פעילה'),
                ),
              ),
              OutlinedButton(
                onPressed: _pending || widget.routine.enabled
                    ? null
                    : () => setState(() => _editing = !_editing),
                child: Text(Strings.t('Edit draft', 'עריכת טיוטה')),
              ),
              TextButton(
                onPressed: _pending ? null : widget.onDecline,
                child: Text(Strings.t('Decline', 'דחייה')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
