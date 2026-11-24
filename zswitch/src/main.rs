//! zswitch: a tiny zellij plugin that switches the session on request from the command line.
//!
//! zellij 0.42 has no `zellij action switch-session`, but plugins may switch sessions. So a
//! script (e.g. an fzf picker in a floating pane) sends the target over a pipe:
//!
//!   zellij pipe --plugin file:$HOME/.config/zellij/plugins/zswitch.wasm -- SESSION
//!   zellij pipe --plugin file:... --args cwd=/some/dir,layout=claude -- NEWSESSION
//!
//! An existing (or exited, resurrectable) session is switched to; a new name creates the
//! session, optionally starting in `cwd` with the named layout from ~/.config/zellij/layouts.
//! Needs two permissions, granted once: ChangeApplicationState (switch) and ReadCliPipes.

use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

#[derive(Default)]
struct State {
    granted: bool,
    pending: Vec<(String, BTreeMap<String, String>)>,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _config: BTreeMap<String, String>) {
        subscribe(&[EventType::PermissionRequestResult]);
        request_permission(&[
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        if let Event::PermissionRequestResult(PermissionStatus::Granted) = event {
            self.granted = true;
            for (name, args) in std::mem::take(&mut self.pending) {
                switch(&name, &args);
            }
            hide_self(); // shown only when zellij had to ask for the permissions
        }
        true
    }

    fn pipe(&mut self, msg: PipeMessage) -> bool {
        let name = msg.payload.as_deref().unwrap_or("").trim().to_string();
        if let PipeSource::Cli(id) = &msg.source {
            unblock_cli_pipe_input(id); // let `zellij pipe` return straight away
        }
        if !name.is_empty() {
            if self.granted {
                switch(&name, &msg.args);
            } else {
                self.pending.push((name, msg.args));
            }
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        if !self.granted {
            println!("zswitch needs permission to switch sessions; answer the prompt above.");
        } else {
            println!("zswitch: permissions granted. This pane can be closed.");
        }
    }
}

fn switch(name: &str, args: &BTreeMap<String, String>) {
    let cwd = args.get("cwd").map(PathBuf::from);
    match args.get("layout") {
        Some(layout) => switch_session_with_layout(Some(name), LayoutInfo::File(layout.clone()), cwd),
        None => switch_session_with_cwd(Some(name), cwd),
    }
}
