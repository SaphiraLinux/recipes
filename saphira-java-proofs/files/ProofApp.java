import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/** Real application: threads + crypto provider + jar resource loading. */
public class ProofApp {
    public static void main(String[] args) throws Exception {
        System.out.println("proofapp: java=" + System.getProperty("java.version")
            + " arch=" + System.getProperty("os.arch"));

        // 1. Resource bundled inside the JAR itself.
        var probe = ProofApp.class.getResourceAsStream("/proof.txt");
        if (probe == null) {
            throw new IllegalStateException("jar resource /proof.txt missing");
        }
        String banner = new String(probe.readAllBytes(), StandardCharsets.UTF_8).trim();
        System.out.println("proofapp: resource=[" + banner + "]");

        // 2. SHA-256 over N threads (crypto provider + concurrency).
        int threads = 4;
        int rounds = 2000;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        List<Callable<String>> jobs = new ArrayList<>();
        for (int t = 0; t < threads; t++) {
            final String input = banner + "-worker-" + t;
            jobs.add(() -> {
                MessageDigest sha = MessageDigest.getInstance("SHA-256");
                byte[] digest = input.getBytes(StandardCharsets.UTF_8);
                for (int i = 0; i < rounds; i++) {
                    digest = sha.digest(digest);
                }
                return HexFormat.of().formatHex(digest);
            });
        }
        StringBuilder combined = new StringBuilder();
        for (Future<String> f : pool.invokeAll(jobs)) {
            combined.append(f.get(), 0, 8);
        }
        pool.shutdown();
        System.out.println("proofapp: digest=" + combined);
        System.out.println("PROOF-OK");
    }
}
