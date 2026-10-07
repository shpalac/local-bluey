# Local STT routing

`tool/local_stt.sh start` passes its selected whisper-server port to the shim.
Defaults remain whisper on 8099 and the OpenAI-compatible shim on 8098.
For example:

```sh
STT_UPSTREAM_PORT=8101 tool/local_stt.sh start
```

The shim receives `--upstream http://127.0.0.1:8101/inference`. Only literal
IPv4 loopback HTTP inference URLs are accepted. Redirects and environment
proxies are disabled for uploaded audio.

The launcher checks `/health` for the shim identity and exact upstream URL.
A stale or conflicting service on the shim port causes an explicit failure;
it is not killed or silently reused. Stop your old shim or select a different
`STT_SHIM_PORT`, then start again. A localhost health response is a configuration
check, not authentication of another process running under the same user.

Offline routing regression tests need Python 3. The additional codec smoke
test runs when ffmpeg is installed and otherwise reports a skip. They generate silent WAV
audio and use loopback fake servers, without a microphone or model download:

```sh
python3 -m unittest discover -s tool -p test_stt_shim.py
```

The Flutter test suite runs these fixtures on non-Windows hosts. The fixtures
verify routing and launch configuration, not whisper accuracy or Metal runtime.
