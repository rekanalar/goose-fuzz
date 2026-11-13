// The seed pool that the mutation and dictionary tests start from.
namespace seed_pool;

import std;
import fuzz from "..";

fn seeds16(pool: u8[>..]&, seeds: fuzz::Seed[>..]&) {
    for i in 0..16 {
        pool.push(i as u8);
    }
    var s = fuzz::Seed { };
    s.off = 0;
    s.len = 16;
    s.energy = 5;
    s.hits = 0;
    seeds.push(s);
}
