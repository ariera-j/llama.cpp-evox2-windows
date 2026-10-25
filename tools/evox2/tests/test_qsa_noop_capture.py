"""Compile actual target-gate capture/decode helpers against unmasked API stubs."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class TargetCaptureTests(unittest.TestCase):
    def test_current_batch_last_row_not_negative_absolute_or_capacity(self):
        compiler = shutil.which("g++")
        if not compiler:
            self.skipTest("g++ unavailable; this is an accessor-wiring test, not a GPU gate")
        source = (ROOT / "tests/test-qsa-noop-invalidation.cpp").read_text()
        helpers = source[source.index("static output capture_output("):source.index("static void clear(")]
        fixture = r'''
#include <vector>
#include <string>
#include <stdexcept>
#include <cstdint>
static void require(bool ok, const std::string & s) { if (!ok) throw std::runtime_error(s); }
struct model {};
struct llama_context { model m; int fetched=-99; float hidden[64*3]{}; float logits[5]{1,2,3,4,5}; };
struct output { std::vector<float> logits, hidden; };
struct llama_batch { int n_tokens=0; };
struct common_batch {
    llama_batch b;
    explicit common_batch(llama_context *) {}
    void add(int, int, int, bool) { ++b.n_tokens; }
    int32_t size() const { return b.n_tokens; }
    llama_batch * get() { return &b; }
};
static void llama_synchronize(llama_context *) {}
static const model * llama_get_model(llama_context *c) { return &c->m; }
static const model * llama_model_get_vocab(const model *m) { return m; }
static int llama_vocab_n_tokens(const model *) { return 5; }
static int llama_model_n_embd_out(const model *) { return 3; }
static float * llama_get_logits_ith(llama_context *c, int i) { require(i==-1,"logits selector"); return c->logits; }
static float * llama_get_embeddings_nextn_ith(llama_context *c, int i) {
    c->fetched=i;
    return i<0 || i>=64 ? nullptr : c->hidden+3*i;
}
static constexpr int LLAMA_PROCESS_TYPE_DECODE=0;
static int llama_process(llama_context *c, int, const llama_batch *b) {
    for (auto &x : c->hidden) x=-100;
    for (int i=0;i<b->n_tokens;++i) for(int j=0;j<3;++j) c->hidden[i*3+j]=float(i*3+j);
    return 0;
}
'''
        checks = r'''
int main() {
    llama_context ctx;
    for (const auto & shape : {std::pair<int,int>{0,32},{0,33},{32,3},{35,1},{256,1}}) {
        const auto out=decode(&ctx,shape.first,shape.second);
        require(ctx.fetched==shape.second-1,"wrong current-batch row");
        require(out.logits.size()==5 && out.hidden.size()==3,"wrong output dimensions");
        for(int j=0;j<3;++j) require(out.hidden[j]==float((shape.second-1)*3+j),"stale or wrong hidden row");
    }
    bool rejected=false;
    try { decode(&ctx,0,0); } catch(const std::runtime_error &) { rejected=true; }
    require(rejected,"empty batch accepted");
}
'''
        with tempfile.TemporaryDirectory() as directory:
            src = Path(directory) / "capture.cpp"
            exe = Path(directory) / "capture.exe"
            src.write_text(fixture + helpers + checks)
            subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", str(src), "-o", str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == "__main__":
    unittest.main()
