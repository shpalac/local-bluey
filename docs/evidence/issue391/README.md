# Key recording intent evidence

Actual AudioCapture with injected fake RecorderDriver tests enter permission/start/stop versus send/cancel/fresh hold/disposal. Successful entered start is joined then stopped/deleted for canceled intents; current key send alone owns file transfer. Failed delete retains file for explicit retry. Native partial start/stop uncertainty is retained, blocks new key starts, and cannot be resolved from a later null AudioCapture.stop.

Screenshots use actual FaceScreen with synthetic key owner in a Scaffold, readable Roboto, via KEY_PIXELS=1. Complete failure/pending/recovery/cancel pixels inspected. Main wiring is source-reviewed, not mounted MacHome/native microphone proof. No cross-input capture arbitration or physical erasure/native-stop claim.

Refs-only #391 remains open for capture-contract remainder: AudioCapture does not stop a driver that partially starts then throws; failed stop clears error so later null cannot establish native stop. Face/key share AudioCapture without global arbitration, also excluded. No AudioCapture/face/phone/controller/native implementation changes.
