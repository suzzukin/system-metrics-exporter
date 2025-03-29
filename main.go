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
	URL string `json:"url"`
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
		log.Fatalf("Не удалось открыть файл конфигурации: %v", err)
	}
	defer file.Close()

	var config Config
	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&config); err != nil {
		log.Fatalf("Не удалось прочитать конфигурацию: %v", err)
	}
	return config
}

func runSpeedtest() (float64, error) {
	// Проверяем наличие speedtest-cli
	if _, err := exec.LookPath("speedtest-cli"); err != nil {
		return 0, fmt.Errorf("speedtest-cli не установлен: %v", err)
	}

	// Запускаем speedtest-cli
	cmd := exec.Command("speedtest-cli", "--simple")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("ошибка при запуске speedtest: %v", err)
	}

	// Парсим результат
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "Download:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				speed, err := strconv.ParseFloat(parts[1], 64)
				if err != nil {
					return 0, fmt.Errorf("ошибка при парсинге скорости: %v", err)
				}
				return speed, nil
			}
		}
	}

	return 0, fmt.Errorf("не удалось получить результат speedtest")
}

func collectMetrics(maxBandwidthMbps float64) Metrics {
	const interval = 1 * time.Second
	const duration = 5 * time.Second
	samples := int(duration / interval)

	var cpuTotal, memTotal, netInTotal, netOutTotal float64
	var lastNetIn, lastNetOut uint64

	netIO, err := psnet.IOCounters(false)
	if err != nil {
		log.Println("Ошибка при получении сетевой статистики:", err)
		return Metrics{}
	}
	lastNetIn = netIO[0].BytesRecv
	lastNetOut = netIO[0].BytesSent

	for i := 0; i < samples; i++ {
		// CPU
		cpuPercent, _ := cpu.Percent(time.Second, false)
		cpuTotal += cpuPercent[0]

		// Память
		vm, _ := mem.VirtualMemory()
		memTotal += vm.UsedPercent

		// Сеть
		time.Sleep(interval)
		netIO, err = psnet.IOCounters(false)
		if err != nil {
			log.Println("Ошибка при получении сетевой статистики:", err)
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

	// Запускаем speedtest
	speedtestMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Ошибка при измерении скорости: %v", err)
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

func sendMetrics(url string, metrics Metrics) {
	data, err := json.Marshal(metrics)
	if err != nil {
		log.Println("Ошибка маршалинга JSON:", err)
		return
	}

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(data))
	if err != nil {
		log.Println("Ошибка отправки метрик:", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Println("Ошибка: сервер вернул статус", resp.Status)
	}
}

func main() {
	configPath := flag.String("config", "/var/lib/vpn-metrics/config.json", "Путь к файлу конфигурации")
	flag.Parse()

	config := loadConfig(*configPath)

	// Запускаем speedtest для определения максимальной пропускной способности
	maxBandwidthMbps, err := runSpeedtest()
	if err != nil {
		log.Printf("Ошибка при определении пропускной способности: %v", err)
		maxBandwidthMbps = 1000.0 // Значение по умолчанию
	}
	log.Printf("Максимальная пропускная способность: %.2f Мбит/с", maxBandwidthMbps)

	for {
		metrics := collectMetrics(maxBandwidthMbps)
		log.Printf("Собраны метрики: %+v", metrics)
		sendMetrics(config.URL, metrics)
		time.Sleep(5 * time.Minute)
	}
}
