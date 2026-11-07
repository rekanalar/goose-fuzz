// Read the source site from an abort message.
//
// An abort message ends with "(file:line)". The site is that text.
namespace fuzz;

import std;

// Append "file:line" from the last parenthesis of msg, or "unknown".
fn site_of(msg: const u8[:], out: u8[>..]&) {
    let open = rfind(msg, "(");
    if open >= 0 && msg.len > 0 && msg[msg.len - 1] == ')' {
        let inner = msg[open + 1..msg.len - 1];
        let colon = rfind(inner, ":");
        if colon > 0 {
            let _, ok = parse_int(inner[colon + 1..]);
            if ok {
                out.append(inner);
                return;
            }
        }
    }
    out.append("unknown");
}
