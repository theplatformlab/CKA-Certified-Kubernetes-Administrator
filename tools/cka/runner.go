package main

// Everything that touches the outside world: scripts/lab.sh for items,
// scripts/init-cluster.sh for clusters, the docs-only exam browser.

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

var repoRoot string

func findRepoRoot() string {
	if r := os.Getenv("CKA_REPO"); r != "" {
		return r
	}
	candidates := []string{}
	if exe, err := os.Executable(); err == nil {
		if real, err := filepath.EvalSymlinks(exe); err == nil {
			exe = real
		}
		candidates = append(candidates, filepath.Dir(filepath.Dir(exe)))
	}
	if wd, err := os.Getwd(); err == nil {
		for d := wd; d != "/"; d = filepath.Dir(d) {
			candidates = append(candidates, d)
		}
	}
	for _, c := range candidates {
		if _, err := os.Stat(filepath.Join(c, "scripts", "lab.sh")); err == nil {
			return c
		}
	}
	return "."
}

func homeDir() string {
	h, _ := os.UserHomeDir()
	return h
}

// Cluster names per profile: exams get fresh, separate clusters.
// The environment variables override the names (used for testing).
func clustersFor(mode string) map[string]string {
	env := func(key, def string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		return def
	}
	if mode == "exam" {
		return map[string]string{
			"practice": env("CKA_EXAM_PRACTICE_CLUSTER", "cka-exam"),
			"ops":      env("CKA_EXAM_OPS_CLUSTER", "cka-exam-ops"),
			"cni":      env("CKA_EXAM_CNI_CLUSTER", "cka-exam-cni"),
			"runtime":  env("CKA_EXAM_RUNTIME_CLUSTER", "cka-exam-runtime"),
			"ha":       env("CKA_EXAM_HA_CLUSTER", "cka-exam-ha"),
		}
	}
	return map[string]string{
		"practice": env("CKA_PRACTICE_CLUSTER", "cka-practice"),
		"ops":      env("CKA_OPS_CLUSTER", "cka-ops"),
		"cni":      env("CKA_CNI_CLUSTER", "cka-cni"),
		"runtime":  env("CKA_RUNTIME_CLUSTER", "cka-runtime"),
		"ha":       env("CKA_HA_CLUSTER", "cka-ha"),
	}
}

func nodeNames(cluster string) (cp, w1, w2 string) {
	return cluster + "-control-plane", cluster + "-worker", cluster + "-worker2"
}

// Variables available as {{KEY}} in the item's README.
func itemVars(s *Session, si *SessionItem, it *Item) map[string]string {
	vars := map[string]string{}
	for k, v := range si.Params {
		vars[k] = v
	}
	cluster := s.Clusters[it.Cluster]
	cp, w1, w2 := nodeNames(cluster)
	vars["CLUSTER"] = cluster
	vars["CONTEXT"] = "kind-" + cluster
	vars["NODE_CP"], vars["NODE_W1"], vars["NODE_W2"] = cp, w1, w2
	vars["NODE_CP2"], vars["NODE_CP3"] = cluster+"-control-plane2", cluster+"-control-plane3"
	vars["WORKDIR"] = strings.Replace(si.Workdir, homeDir(), "~", 1)
	return vars
}

func labEnv(s *Session, si *SessionItem) []string {
	env := os.Environ()
	env = append(env,
		"CKA_PRACTICE_CLUSTER="+s.Clusters["practice"],
		"CKA_OPS_CLUSTER="+s.Clusters["ops"],
		"WORKDIR="+si.Workdir,
		fmt.Sprintf("CKA_SEED=%d", si.Seed%32768),
		"CKA_PARAMS=1",
	)
	for _, p := range []string{"cni", "runtime", "ha"} {
		if c := s.Clusters[p]; c != "" {
			env = append(env, fmt.Sprintf("CKA_%s_CLUSTER=%s", strings.ToUpper(p), c))
		}
	}
	if s.Network != "" {
		env = append(env, "KIND_EXPERIMENTAL_DOCKER_NETWORK="+s.Network)
	}
	keys := make([]string, 0, len(si.Params))
	for k := range si.Params {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		env = append(env, k+"="+si.Params[k])
	}
	return env
}

func runLab(action string, it *Item, env []string, out io.Writer) error {
	cmd := exec.Command("bash", filepath.Join(repoRoot, "scripts", "lab.sh"), action, it.Dir)
	cmd.Env = env
	cmd.Stdout, cmd.Stderr = out, out
	return cmd.Run()
}

// EvalParams runs the item's lab_params with the given seed.
func EvalParams(it *Item, seed int64) (map[string]string, error) {
	lab, err := os.ReadFile(filepath.Join(it.Dir, "lab.sh"))
	if err != nil || !bytes.Contains(lab, []byte("lab_params()")) {
		return map[string]string{}, nil
	}
	cmd := exec.Command("bash", filepath.Join(repoRoot, "scripts", "lab.sh"), "params", it.Dir)
	cmd.Env = append(os.Environ(), fmt.Sprintf("CKA_SEED=%d", seed%32768))
	raw, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("params of %s: %w", it.ID, err)
	}
	params := map[string]string{}
	sc := bufio.NewScanner(bytes.NewReader(raw))
	for sc.Scan() {
		if k, v, ok := strings.Cut(sc.Text(), "="); ok && k != "" {
			params[k] = v
		}
	}
	return params, nil
}

// RunCheck runs the item's validator and returns the individual results.
func RunCheck(s *Session, si *SessionItem, it *Item) ([]CheckResult, string, error) {
	f, err := os.CreateTemp("", "cka-check-*.tsv")
	if err != nil {
		return nil, "", err
	}
	f.Close()
	defer os.Remove(f.Name())
	var out bytes.Buffer
	env := append(labEnv(s, si), "CKA_RESULTS_FILE="+f.Name())
	runErr := runLab("check", it, env, &out)
	raw, _ := os.ReadFile(f.Name())
	var results []CheckResult
	for _, line := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) < 2 {
			continue
		}
		r := CheckResult{Pass: parts[0] == "PASS", Desc: parts[1]}
		if len(parts) == 3 {
			r.Detail = parts[2]
		}
		results = append(results, r)
	}
	if len(results) == 0 {
		// The validator could not run at all (e.g. cluster missing).
		results = []CheckResult{{Pass: false, Desc: "validator ran", Detail: lastLines(out.String(), 3)}}
		if runErr == nil {
			runErr = fmt.Errorf("no check results")
		}
		return results, out.String(), runErr
	}
	return results, out.String(), nil
}

func lastLines(s string, n int) string {
	lines := strings.Split(strings.TrimSpace(stripANSI(s)), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, " | ")
}

// ---- Clusters ----------------------------------------------------------------

func clusterExists(name string) bool {
	out, err := exec.Command("kind", "get", "clusters").Output()
	if err != nil {
		return false
	}
	for _, l := range strings.Split(string(out), "\n") {
		if strings.TrimSpace(l) == name {
			return true
		}
	}
	return false
}

func createCluster(profile, name, network string, recreate bool, out io.Writer) error {
	args := []string{filepath.Join(repoRoot, "scripts", "init-cluster.sh"), "--profile", profile}
	if recreate {
		args = append(args, "--recreate")
	}
	cmd := exec.Command("bash", args...)
	cmd.Env = append(os.Environ(), "CLUSTER_NAME="+name, "CKA_KEEP_CONTEXT=1")
	if network != "" {
		cmd.Env = append(cmd.Env, "KIND_EXPERIMENTAL_DOCKER_NETWORK="+network)
	}
	cmd.Stdout, cmd.Stderr = out, out
	return cmd.Run()
}

// Cluster containers by role: load balancer and control planes first when
// starting (the API server must come up before the kubelets reconnect).
func clusterContainers(name string) (first, rest []string) {
	out, err := exec.Command("docker", "ps", "-a", "--filter", "label=io.x-k8s.kind.cluster="+name,
		"--format", `{{.Names}} {{.Label "io.x-k8s.kind.role"}}`).Output()
	if err != nil {
		return nil, nil
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Fields(line)
		if len(f) == 0 {
			continue
		}
		if len(f) > 1 && (f[1] == "control-plane" || f[1] == "external-load-balancer") {
			first = append(first, f[0])
		} else {
			rest = append(rest, f[0])
		}
	}
	return first, rest
}

// clusterRunning: true if the cluster exists and its containers are up.
func clusterRunning(name string) bool {
	out, err := exec.Command("docker", "ps", "--filter", "label=io.x-k8s.kind.cluster="+name, "-q").Output()
	return err == nil && len(bytes.TrimSpace(out)) > 0
}

// stopCluster stops the node containers (state is kept, memory is freed).
func stopCluster(name string) error {
	first, rest := clusterContainers(name)
	all := append(rest, first...)
	if len(all) == 0 {
		return nil
	}
	return exec.Command("docker", append([]string{"stop", "-t", "20"}, all...)...).Run()
}

// startCluster starts a stopped cluster and waits (up to ~1.5 minutes) for the
// API server. A cluster whose control plane an exam task broke on purpose
// never gets ready, so not answering is reported but is not an error.
func startCluster(name string, log func(string)) error {
	first, rest := clusterContainers(name)
	if len(first)+len(rest) == 0 {
		return fmt.Errorf("cluster %s does not exist", name)
	}
	log("Starting cluster " + name + " ...")
	if err := exec.Command("docker", append([]string{"start"}, first...)...).Run(); err != nil {
		return err
	}
	if len(rest) > 0 {
		if err := exec.Command("docker", append([]string{"start"}, rest...)...).Run(); err != nil {
			return err
		}
	}
	ctx := "kind-" + name
	for i := 0; i < 25; i++ {
		if exec.Command("kubectl", "--context", ctx, "--request-timeout=5s", "get", "--raw", "/readyz").Run() == nil {
			exec.Command("kubectl", "--context", ctx, "wait", "--for=condition=Ready", "nodes", "--all", "--timeout=90s").Run()
			log("Cluster " + name + " is up")
			return nil
		}
		time.Sleep(3 * time.Second)
	}
	log("Cluster " + name + " started, but its API server doesn't answer (expected if a task broke it)")
	return nil
}

// startClusters starts several clusters in parallel.
func startClusters(names []string, log func(string)) error {
	var wg sync.WaitGroup
	errs := make(chan error, len(names))
	for _, n := range names {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			if err := startCluster(n, log); err != nil {
				errs <- err
			}
		}(n)
	}
	wg.Wait()
	close(errs)
	return <-errs
}

// Profiles used by a session's items.
func sessionProfiles(s *Session, items []*Item) []string {
	seen := map[string]bool{}
	var out []string
	for _, si := range s.Items {
		if it := findItem(items, si.ItemID); it != nil && !seen[it.Cluster] {
			seen[it.Cluster] = true
			out = append(out, it.Cluster)
		}
	}
	sort.Strings(out)
	return out
}

func deleteCluster(name string, out io.Writer) error {
	cmd := exec.Command("kind", "delete", "cluster", "--name", name)
	cmd.Stdout, cmd.Stderr = out, out
	return cmd.Run()
}

func browser(action string) error {
	cmd := exec.Command("bash", filepath.Join(repoRoot, "scripts", "exam", "browser.sh"), action)
	var buf bytes.Buffer
	cmd.Stdout, cmd.Stderr = &buf, &buf
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%v: %s", err, lastLines(buf.String(), 2))
	}
	return nil
}

// ---- Session preparation -----------------------------------------------------

// Prepare creates the clusters a session needs and runs every item's setup.
// fresh: recreate the clusters (exam). log receives progress lines.
func Prepare(s *Session, items []*Item, fresh bool, log func(string)) error {
	byID := map[string]*Item{}
	for _, it := range items {
		byID[it.ID] = it
	}
	profiles := map[string]bool{}
	for _, si := range s.Items {
		profiles[byID[si.ItemID].Cluster] = true
	}

	// Clusters (in parallel).
	var wg sync.WaitGroup
	errs := make(chan error, len(profiles))
	for p := range profiles {
		name := s.Clusters[p]
		if name == "" {
			return fmt.Errorf("no cluster for profile %s", p)
		}
		if !fresh && clusterExists(name) {
			if !clusterRunning(name) {
				if err := startCluster(name, log); err != nil {
					return err
				}
			} else {
				log(fmt.Sprintf("Cluster %s is up", name))
			}
			continue
		}
		log(fmt.Sprintf("Creating cluster %s (profile %s) — takes 1-2 minutes ...", name, p))
		wg.Add(1)
		go func(p, name string) {
			defer wg.Done()
			logFile := filepath.Join(os.TempDir(), "cka-cluster-"+name+".log")
			f, _ := os.Create(logFile)
			defer f.Close()
			if err := createCluster(p, name, s.Network, fresh, f); err != nil {
				errs <- fmt.Errorf("creating %s failed, see %s", name, logFile)
				return
			}
			log(fmt.Sprintf("Cluster %s ready", name))
		}(p, name)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		return err
	}

	// Item setups: independent items on the practice cluster run in parallel;
	// items on the other clusters change the nodes/control plane, so they run
	// one by one, and "late" items (which break the API server) last.
	for _, si := range s.Items {
		os.RemoveAll(si.Workdir)
		os.MkdirAll(si.Workdir, 0o755)
	}
	setup := func(si *SessionItem) {
		it := byID[si.ItemID]
		var out bytes.Buffer
		if !fresh {
			runLab("cleanup", it, labEnv(s, si), io.Discard)
		}
		if err := runLab("setup", it, labEnv(s, si), &out); err != nil {
			si.SetupError = lastLines(out.String(), 6)
			log(fmt.Sprintf("✗ setup of %s failed: %s", si.ItemID, lastLines(out.String(), 2)))
			return
		}
		si.SetupError = ""
		log("✓ " + it.Title)
	}
	sem := make(chan struct{}, 6)
	var parallel, sequential []*SessionItem
	for _, si := range s.Items {
		if byID[si.ItemID].Cluster == "practice" && byID[si.ItemID].Order != "late" {
			parallel = append(parallel, si)
		} else {
			sequential = append(sequential, si)
		}
	}
	sort.SliceStable(sequential, func(i, j int) bool {
		return byID[sequential[i].ItemID].Order != "late" && byID[sequential[j].ItemID].Order == "late"
	})
	var pwg sync.WaitGroup
	for _, si := range parallel {
		pwg.Add(1)
		go func(si *SessionItem) {
			defer pwg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			setup(si)
		}(si)
	}
	for _, si := range sequential {
		setup(si)
	}
	pwg.Wait()
	recordBaselines(s, byID, log)
	return nil
}

// recordBaselines runs the checks of exercise items once after setup, when
// their pods have settled. Exercises have no check_gate, so grading uses the
// baseline to give an untouched exercise 0 points (see ApplyBaseline).
func recordBaselines(s *Session, byID map[string]*Item, log func(string)) {
	var wg sync.WaitGroup
	for _, si := range s.Items {
		it := byID[si.ItemID]
		if !it.Exercise || si.SetupError != "" {
			continue
		}
		wg.Add(1)
		go func(si *SessionItem, it *Item) {
			defer wg.Done()
			ctx := "kind-" + s.Clusters[it.Cluster]
			for _, ns := range it.Namespaces {
				exec.Command("kubectl", "--context", ctx, "-n", Render(ns, si.Params, nil), "wait",
					"--for=condition=Ready", "pods", "--all", "--timeout=60s").Run()
			}
			if results, _, err := RunCheck(s, si, it); err == nil {
				si.Baseline = nil
				for _, r := range results {
					if r.Pass {
						si.Baseline = append(si.Baseline, r.Desc)
					}
				}
			}
		}(si, it)
	}
	if len(s.Items) > 0 {
		log("Recording the starting state of exercise items ...")
	}
	wg.Wait()
}

// Cleanup runs every item's cleanup (practice sessions, after grading).
func Cleanup(s *Session, items []*Item, log func(string)) {
	for _, si := range s.Items {
		it := findItem(items, si.ItemID)
		if it == nil {
			continue
		}
		var out bytes.Buffer
		if err := runLab("cleanup", it, labEnv(s, si), &out); err != nil {
			log(fmt.Sprintf("✗ cleanup of %s: %s", si.ItemID, lastLines(out.String(), 2)))
		} else {
			log("✓ cleaned up " + it.Title)
		}
	}
}

func stripANSI(s string) string {
	var b strings.Builder
	esc := false
	for _, r := range s {
		switch {
		case r == 0x1b:
			esc = true
		case esc && (r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z'):
			esc = false
		case esc:
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
