***REMOVED*** Local Headroom Setup

Setting up Headroom on the local NixOS machine to wrap opencode.

***REMOVED******REMOVED*** Installation

```bash
pip install "headroom-ai[all]"
```

***REMOVED******REMOVED*** Wrap opencode

```bash
headroom wrap opencode
```

This starts a local proxy on port 8787 and configures opencode to route through it.
The proxy listens on `127.0.0.1:8787` — only accessible from the local machine.

***REMOVED******REMOVED*** Verify

```bash
***REMOVED*** Check everything is wired up correctly
headroom doctor

***REMOVED*** View compression stats from recent sessions
headroom perf

***REMOVED*** Open the live dashboard
headroom dashboard
```

***REMOVED******REMOVED*** Undo

```bash
headroom unwrap opencode
```

This restores opencode's original configuration and stops the proxy.

***REMOVED******REMOVED*** Advanced: Learn from past sessions

Headroom can analyze past agent sessions to improve its compression strategies.

```bash
***REMOVED*** Run the learning pass (dry run — shows what it would change)
headroom learn

***REMOVED*** Apply learned improvements
headroom learn --verbosity --apply
```

***REMOVED******REMOVED*** Persistent Service via Nix / Home Manager

To keep Headroom running as a background service (survives reboots), add it to
your Home Manager configuration:

```nix
***REMOVED*** home.nix or wherever your HM config lives
{
  ***REMOVED*** Headroom proxy service
  systemd.user.services.headroom = {
    Unit = {
      Description = "Headroom token compression proxy";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.headroom-ai}/bin/headroom serve --config ${./headroom/local-config.yaml}";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "HEADROOM_OUTPUT_SHAPER=1"
      ];
    };
    Install = {
      WantedBy = [ "default.target" };
    };
  };
}
```

Then rebuild:

```bash
home-manager switch
```

Check status:

```bash
systemctl --user status headroom
journalctl --user -u headroom -f
```

***REMOVED******REMOVED*** Output Shaping

Enable output token reduction to make the LLM produce shorter responses on
routine turns:

```bash
***REMOVED*** Via environment variable
export HEADROOM_OUTPUT_SHAPER=1

***REMOVED*** Or in local-config.yaml under output_shaping:
***REMOVED***   enabled: true
***REMOVED***   verbosity: concise
```

When `effort_routing` is enabled, Headroom also reduces thinking/reasoning effort
on low-complexity turns, further cutting output tokens.

***REMOVED******REMOVED*** Cross-Agent Memory

If you run multiple agents (e.g., opencode + a second agent for testing), they
can share context through Headroom's memory store.

In `local-config.yaml`:

```yaml
memory:
  enabled: true
  store_type: sqlite
  path: ~/.headroom/memory
  learn_enabled: true
```

Both agents must route through the same Headroom proxy instance. The proxy
automatically injects relevant shared context into each agent's prompts.

To inspect what's stored:

```bash
headroom memory list
headroom memory inspect <id>
```

***REMOVED******REMOVED*** Config Reference

See [`local-config.yaml`](local-config.yaml) for the full proxy configuration.
