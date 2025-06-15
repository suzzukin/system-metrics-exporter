package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/cpu"
	"github.com/shirou/gopsutil/mem"
	psnet "github.com/shirou/gopsutil/net"
)

type Config struct {
	URL            string `json:"server_url"`
	Token          string `json:"api_token"`
	ReportInterval int    `json:"report_interval"`
}

type Metrics struct {
	CPU           float64 `json:"cpu_percent"`
	Memory        float64 `json:"memory_percent"`
	NetInPercent  float64 `json:"net_in_percent"`
	NetOutPercent float64 `json:"net_out_percent"`
	Speedtest     float64 `json:"speedtest_mbps"`
}

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
	return config
}

func runSpeedtest() (float64, error) {
	// Check if speedtest-cli is installed
	if _, err := exec.LookPath("speedtest-cli"); err != nil {
		return 0, fmt.Errorf("speedtest-cli is not installed: %v", err)
	}

	// Run speedtest-cli
	cmd := exec.Command("speedtest-cli", "--simple")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("error running speedtest: %v", err)
	}

	// Parse result
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

func collectMetrics(maxBandwidthMbps float64) Metrics {
	const interval = 1 * time.Second
	const duration = 5 * time.Second
	samples := int(duration / interval)

	var cpuTotal, memTotal, netInTotal, netOutTotal float64
	var lastNetIn, lastNetOut uint64

	netIO, err := psnet.IOCounters(false)
	if err != nil {
		log.Println("Error getting network statistics:", err)
		return Metrics{}
	}
	lastNetIn = netIO[0].BytesRecv
	lastNetOut = netIO[0].BytesSent

	for i := 0; i < samples; i++ {
		// CPU
		cpuPercent, _ := cpu.Percent(time.Second, false)
		cpuTotal += cpuPercent[0]

		// Memory
		vm, _ := mem.VirtualMemory()
		memTotal += vm.UsedPercent

		// Network
		time.Sleep(interval)
		netIO, err = psnet.IOCounters(false)
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

	avgCPU := cpuTotal / float64(samples)
	avgMemory := memTotal / float64(samples)
	avgNetInMbps := netInTotal / float64(samples)
	avgNetOutMbps := netOutTotal / float64(samples)

	netInPercent := (avgNetInMbps / maxBandwidthMbps) * 100
	netOutPercent := (avgNetOutMbps / maxBandwidthMbps) * 100

	// Run speedtest
	speedtestMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Error measuring speed: %v", err)
		speedtestMbps = 0
	}

	return Metrics{
		CPU:           avgCPU,
		Memory:        avgMemory,
		NetInPercent:  netInPercent,
		NetOutPercent: netOutPercent,
		Speedtest:     speedtestMbps,
	}
}

func sendMetrics(url string, token string, metrics Metrics) {
	data, err := json.Marshal(metrics)
	fmt.Println("sending metrics: ", string(data))
	if err != nil {
		log.Println("Error marshaling JSON:", err)
		return
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(data))
	if err != nil {
		log.Println("Error creating request:", err)
		return
	}

	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", token)
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Println("Error sending metrics:", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Println("Error: server returned status", resp.Status)
	}
}

func main() {
	configPath := flag.String("config", "/var/lib/vpn-metrics/config.json", "Path to config file")
	flag.Parse()

	config := loadConfig(*configPath)

	// Run speedtest to determine maximum bandwidth
	maxBandwidthMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Error determining bandwidth: %v", err)
		maxBandwidthMbps = 1000.0 // Default value
	}
	log.Printf("Maximum bandwidth: %.2f Mbps", maxBandwidthMbps)

	// Send metrics immediately after startup
	log.Println("Sending initial metrics...")
	metrics := collectMetrics(maxBandwidthMbps)
	log.Printf("Initial metrics: %+v", metrics)
	sendMetrics(config.URL, config.Token, metrics)

	// Start regular metrics collection
	for {
		time.Sleep(time.Duration(config.ReportInterval) * time.Second)
		metrics := collectMetrics(maxBandwidthMbps)
		log.Printf("Collected metrics: %+v", metrics)
		sendMetrics(config.URL, config.Token, metrics)
	}
}
