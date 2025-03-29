package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"

	// "io/ioutil"
	"log"
	"net/http"
	"os"
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

func getMaxBandwidthMbps() float64 {
	interfaces, err := psnet.Interfaces()
	if err != nil {
		log.Println("Ошибка при получении интерфейсов:", err)
		return 1000.0 // Значение по умолчанию
	}

	for _, iface := range interfaces {
		isUp := false
		isLoopback := false
		for _, flag := range iface.Flags {
			if flag == "up" {
				isUp = true
			}
			if flag == "loopback" {
				isLoopback = true
			}
		}
		if !isUp || isLoopback {
			continue
		}
		speedFile := fmt.Sprintf("/sys/class/net/%s/speed", iface.Name)
		speedData, err := os.ReadFile(speedFile)
		if err != nil {
			continue
		}
		speedStr := strings.TrimSpace(string(speedData))
		speed, err := strconv.Atoi(speedStr)
		if err != nil {
			continue
		}
		return float64(speed)
	}
	log.Println("Не удалось определить скорость, используется значение по умолчанию")
	return 1000.0
}

func collectMetrics(maxBandwidthMbps float64) Metrics {
	const interval = 1 * time.Second
	const duration = 5 * time.Second
	samples := int(duration / interval)

	var cpuTotal, memTotal, netInTotal, netOutTotal float64
	var lastNetIn, lastNetOut uint64

	netIO, err := psnet.IOCounters(false) // Используем psnet вместо net
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
		netIO, err = psnet.IOCounters(false) // Используем psnet вместо net
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

	return Metrics{
		CPU:           avgCPU,
		Memory:        avgMemory,
		NetInPercent:  netInPercent,
		NetOutPercent: netOutPercent,
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
	maxBandwidthMbps := getMaxBandwidthMbps()
	log.Printf("Максимальная пропускная способность: %.2f Мбит/с", maxBandwidthMbps)

	for {
		metrics := collectMetrics(maxBandwidthMbps)
		log.Printf("Собраны метрики: %+v", metrics)
		sendMetrics(config.URL, metrics)
		time.Sleep(5 * time.Minute)
	}
}
