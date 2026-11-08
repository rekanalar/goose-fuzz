// The coverage of the program.
//
// The C part of the package records the code that each input reaches.
// A program that was built without the coverage flag never calls the
// callback of the sanitizer, and the counters stay at zero.
//
// The compiler of the generated C holds no line directive, so the
// counters name no source line.
//
// The extern names are the names of the C symbols, because Goose
// v2026.3 has no form that binds a Goose name to another C name.
namespace fuzz;

extern fn gs_cov_reset();
extern fn gs_cov_begin();
extern fn gs_cov_end() -> u64;
extern fn gs_cov_total_edges() -> u64;
extern fn gs_cov_lost_edges() -> u64;
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

// Close the bracket of one input. It gives the count of the edges that
// no earlier input reached. The worker of the input closes it. The main
// thread closes it after an abort.
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

// True when the program was built with the coverage flag.
fn cov_live() -> bool {
    return gs_cov_live();
}

// Write the path of the compiler wrapper of the package into out. It
// gives false when the path does not have the expected form.
fn coverage_path(out: u8[>..]&) -> bool {
    return gs_cov_script(out);
}
