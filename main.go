package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"github.com/shirou/gopsutil/v3/process"
)

// Version will be set during build
var Version = "1.0.0"

type Config struct {
	URL             string `json:"URL"`
	Token           string `json:"token"`
	ReportInterval  int    `json:"report_interval"`
	CollectInterval int    `json:"collect_interval"`
	CollectDuration int    `json:"collect_duration"`
}

type Metrics struct {
	// Basic metrics
	CPU           float64 `json:"cpu_percent"`
	Memory        float64 `json:"memory_percent"`
	NetInPercent  float64 `json:"net_in_percent"`
	NetOutPercent float64 `json:"net_out_percent"`
	Speedtest     float64 `json:"speedtest_mbps"`

	// System metrics
	Uptime          float64 `json:"uptime_seconds"`
	LoadAverage     float64 `json:"load_average"`
	DiskUsage       float64 `json:"disk_usage_percent"`
	FileDescriptors int     `json:"file_descriptors"`

	// Network metrics
	ActiveConnections int                      `json:"active_connections"`
	TCPConnections    int                      `json:"tcp_connections"`
	UDPConnections    int                      `json:"udp_connections"`
	NetworkLatency    float64                  `json:"network_latency"`
	InterfaceStats    map[string]InterfaceStat `json:"interface_stats"`
}

type InterfaceStat struct {
	BytesIn    uint64 `json:"bytes_in"`
	BytesOut   uint64 `json:"bytes_out"`
	PacketsIn  uint64 `json:"packets_in"`
	PacketsOut uint64 `json:"packets_out"`
	ErrorsIn   uint64 `json:"errors_in"`
	ErrorsOut  uint64 `json:"errors_out"`
}

var (
	httpClient = &http.Client{
		Timeout: 30 * time.Second,
	}
)

func loadConfig(configPath string) Config {
	file, err := os.Open(configPath)
	if err != nil {
		log.Fatalf("Failed to open config file: %v", err)
	}
	defer file.Close()

	var config Config
	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&config); err != nil {
		log.Fatalf("Failed to read config: %v", err)
	}

	// Set defaults
	if config.CollectInterval == 0 {
		config.CollectInterval = 1
	}
	if config.CollectDuration == 0 {
		config.CollectDuration = 5
	}
	if config.ReportInterval == 0 {
		config.ReportInterval = 300
	}

	return config
}

func runSpeedtest() (float64, error) {
	if _, err := exec.LookPath("speedtest-cli"); err != nil {
		return 0, fmt.Errorf("speedtest-cli is not installed: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "speedtest-cli", "--simple")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("error running speedtest: %v", err)
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "Download:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				speed, err := strconv.ParseFloat(parts[1], 64)
				if err != nil {
					return 0, fmt.Errorf("error parsing speed: %v", err)
				}
				return speed, nil
			}
		}
	}

	return 0, fmt.Errorf("failed to get speedtest result")
}

func getSystemMetrics() (float64, float64, float64, float64) {
	// CPU Load
	loadAvg, _ := load.Avg()

	// Memory
	vm, _ := mem.VirtualMemory()

	// Disk usage
	diskUsage, _ := disk.Usage("/")

	// File descriptors
	fdCount := 0.0
	if proc, err := process.NewProcess(int32(os.Getpid())); err == nil {
		if fds, err := proc.NumFDs(); err == nil {
			fdCount = float64(fds)
		}
	}

	return loadAvg.Load1, vm.UsedPercent, diskUsage.UsedPercent, fdCount
}

func getNetworkMetrics() (int, int, int, float64, map[string]InterfaceStat) {
	// Get all network connections
	conns, _ := net.Connections("all")

	// Count TCP and UDP connections
	tcpCount := 0
	udpCount := 0
	for _, conn := range conns {
		if conn.Type == syscall.SOCK_STREAM {
			tcpCount++
		} else if conn.Type == syscall.SOCK_DGRAM {
			udpCount++
		}
	}

	// Get interface statistics
	ioStats, _ := net.IOCounters(true)
	interfaceStats := make(map[string]InterfaceStat)
	for _, stat := range ioStats {
		interfaceStats[stat.Name] = InterfaceStat{
			BytesIn:    stat.BytesRecv,
			BytesOut:   stat.BytesSent,
			PacketsIn:  stat.PacketsRecv,
			PacketsOut: stat.PacketsSent,
			ErrorsIn:   stat.Errin,
			ErrorsOut:  stat.Errout,
		}
	}

	// Simple latency check (ping to 8.8.8.8)
	latency := 0.0
	if cmd := exec.Command("ping", "-c", "1", "8.8.8.8"); cmd.Run() == nil {
		if output, err := cmd.CombinedOutput(); err == nil {
			if strings.Contains(string(output), "time=") {
				parts := strings.Split(string(output), "time=")
				if len(parts) > 1 {
					latencyStr := strings.Split(parts[1], " ")[0]
					latency, _ = strconv.ParseFloat(latencyStr, 64)
				}
			}
		}
	}

	return len(conns), tcpCount, udpCount, latency, interfaceStats
}

func collectMetrics(maxBandwidthMbps float64, config Config) Metrics {
	interval := time.Duration(config.CollectInterval) * time.Second
	duration := time.Duration(config.CollectDuration) * time.Second
	samples := int(duration / interval)

	var cpuTotal, memTotal, netInTotal, netOutTotal float64
	var lastNetIn, lastNetOut uint64

	metrics := Metrics{
		CPU:           0,
		Memory:        0,
		NetInPercent:  0,
		NetOutPercent: 0,
		Speedtest:     0,
	}

	// Get initial network stats
	netIO, err := net.IOCounters(false)
	if err != nil {
		log.Println("Error getting network statistics:", err)
		return metrics
	}
	lastNetIn = netIO[0].BytesRecv
	lastNetOut = netIO[0].BytesSent

	// Collect basic metrics
	for i := 0; i < samples; i++ {
		cpuPercent, err := cpu.Percent(time.Second, false)
		if err == nil && len(cpuPercent) > 0 {
			cpuTotal += cpuPercent[0]
		}

		vm, err := mem.VirtualMemory()
		if err == nil {
			memTotal += vm.UsedPercent
		}

		time.Sleep(interval)
		netIO, err = net.IOCounters(false)
		if err != nil {
			log.Println("Error getting network statistics:", err)
			continue
		}
		currentNetIn := netIO[0].BytesRecv
		currentNetOut := netIO[0].BytesSent

		netInMbps := float64(currentNetIn-lastNetIn) * 8 / (1024 * 1024) / interval.Seconds()
		netOutMbps := float64(currentNetOut-lastNetOut) * 8 / (1024 * 1024) / interval.Seconds()
		netInTotal += netInMbps
		netOutTotal += netOutMbps

		lastNetIn = currentNetIn
		lastNetOut = currentNetOut
	}

	// Calculate averages
	if samples > 0 {
		metrics.CPU = cpuTotal / float64(samples)
		metrics.Memory = memTotal / float64(samples)
		metrics.NetInPercent = (netInTotal / float64(samples) / maxBandwidthMbps) * 100
		metrics.NetOutPercent = (netOutTotal / float64(samples) / maxBandwidthMbps) * 100
	}

	// Get system metrics
	loadAvg, diskUsage, fdCount, _ := getSystemMetrics()
	metrics.LoadAverage = loadAvg
	metrics.DiskUsage = diskUsage
	metrics.FileDescriptors = int(fdCount)

	// Get network metrics
	activeConns, tcpConns, udpConns, latency, ifStats := getNetworkMetrics()
	metrics.ActiveConnections = activeConns
	metrics.TCPConnections = tcpConns
	metrics.UDPConnections = udpConns
	metrics.NetworkLatency = latency
	metrics.InterfaceStats = ifStats

	// Run speedtest
	speedtestMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Error measuring speed: %v", err)
	} else {
		metrics.Speedtest = speedtestMbps
	}

	return metrics
}

func sendMetrics(ctx context.Context, url string, token string, metrics Metrics) {
	data, err := json.Marshal(metrics)
	if err != nil {
		log.Println("Error marshaling JSON:", err)
		return
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(data))
	if err != nil {
		log.Println("Error creating request:", err)
		return
	}

	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", token)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		log.Println("Error sending metrics:", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("Error: server returned status %d", resp.StatusCode)
	}
}

func main() {
	configPath := flag.String("config", "/etc/node-metrics-exporter/config.json", "Path to config file")
	version := flag.Bool("version", false, "Print version and exit")
	flag.Parse()

	if *version {
		fmt.Println(Version)
		os.Exit(0)
	}

	// Load configuration
	config := loadConfig(*configPath)

	maxBandwidthMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Error determining bandwidth: %v", err)
		maxBandwidthMbps = 1000.0
	}
	log.Printf("Maximum bandwidth: %.2f Mbps", maxBandwidthMbps)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		log.Println("Received shutdown signal, cleaning up...")
		cancel()
	}()

	log.Println("Sending initial metrics...")
	metrics := collectMetrics(maxBandwidthMbps, config)
	log.Printf("Initial metrics: %+v", metrics)
	sendMetrics(ctx, config.URL, config.Token, metrics)

	ticker := time.NewTicker(time.Duration(config.ReportInterval) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			metrics := collectMetrics(maxBandwidthMbps, config)
			log.Printf("Collected metrics: %+v", metrics)
			sendMetrics(ctx, config.URL, config.Token, metrics)
		case <-ctx.Done():
			log.Println("Shutting down...")
			return
		}
	}
}
