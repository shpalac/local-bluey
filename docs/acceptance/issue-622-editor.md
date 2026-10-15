# Issue #622 bounded editor slice

The existing disabled Routine review card now offers an optional edit panel with before/after instructions. Validation delegates to RoutineProposal. The callback receives a disabled proposal; no activation, storage mutation, or host actions occur in the editor.

This does not implement a full Workflow DSL steps/conditions/permissions editor. Security and full platform compatibility remain acceptance gaps.

Rollback: revert the UI addition; no persisted schema was changed.
