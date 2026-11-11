// The coverage of the program.
//
// The C part of the package records the code that each input reaches,
// and how often each piece ran. A program that was built without the
// coverage flag never calls the callback of the sanitizer, and the
// counters stay at zero.
//
// The compiler of the generated C holds no line directive, so the
// counters name no source line.
//
// The extern names are the names of the C symbols, because Goose
// v2026.3 has no form that binds a Goose name to another C name.
namespace fuzz;

extern fn gs_cov_reset();
extern fn gs_cov_begin();
extern fn gs_cov_attach();
extern fn gs_cov_detach();
extern fn gs_cov_end() -> u64;
extern fn gs_cov_total_edges() -> u64;
extern fn gs_cov_lost_edges() -> u64;
extern fn gs_cov_class_edges(cls: i64) -> u64;
extern fn gs_cov_live() -> bool;
extern fn gs_cov_script(out: u8[>..]&) -> bool;

// Empty the table of the edges and the counters. A run calls it at its
// start, so that the counts belong to one run.
fn cov_reset() {
    gs_cov_reset();
}

// Open the bracket of one input.
fn cov_begin() {
    gs_cov_begin();
}

// Start the recording on the calling thread. The bracket stays as it
// is. The thread that owns the bracket opens it with cov_begin. Each
// worker then calls cov_attach at its start and cov_detach at its end,
// and the owner closes the bracket after it joined the workers. The
// edges of all the attached threads join one bracket.
fn cov_attach() {
    gs_cov_attach();
}

// Stop the recording on the calling thread. Its edges stay in the
// bracket.
fn cov_detach() {
    gs_cov_detach();
}

// Close the bracket of one input. It gives the count of the edges
// whose class of hit count rose above the class of any earlier input
// of the run. A new edge rises too. The worker of the input closes it.
// The main thread closes it after an abort.
fn cov_end() -> u64 {
    return gs_cov_end();
}

// The count of the distinct edges since the last reset.
fn cov_total() -> u64 {
    return gs_cov_total_edges();
}

// The count of the addresses that found the table full.
fn cov_lost() -> u64 {
    return gs_cov_lost_edges();
}

// The count of the edges whose highest class is cls, from 1 to 8. The
// class of an edge is the class of its highest hit count of the run.
fn cov_class_edges(cls: i64) -> u64 {
    return gs_cov_class_edges(cls);
}

// True when the program was built with the coverage flag.
fn cov_live() -> bool {
    return gs_cov_live();
}

// Write the path of the compiler wrapper of the package into out. It
// gives false when the path does not have the expected form.
fn coverage_path(out: u8[>..]&) -> bool {
    return gs_cov_script(out);
}
