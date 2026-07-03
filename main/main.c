/*
 * sup-esurf-controller
 * ESP32 HID Host для подключения к пульту BT13
 * Универсальное управление бесщеточным двигателем (для ZS-X11FV3, ZS-X11H и аналогов)
 *
 * Автор: sanfisko
 * Дата: 2026-07-03
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_bt_device.h"
#include "esp_hidh.h"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_timer.h"

static const char *TAG = "BT_MOTOR_CONTROL";

// ==============================================================================
// УНИВЕРСАЛЬНЫЕ НАСТРОЙКИ ОБОРУДОВАНИЯ И КОНТРОЛЛЕРА
// ==============================================================================

// Пины ESP32 для управления
#define MOTOR_SPEED_PIN     GPIO_NUM_25
#define MOTOR_DIR_PIN       GPIO_NUM_26
#define LED_PIN             GPIO_NUM_2

// Настройки ШИМ (PWM)
// Частота 1000 Гц универсальна: подходит и для старых плат (50Hz-20kHz), и для новых (1KHz-10KHz)
#define LEDC_FREQUENCY      1000 
#define LEDC_TIMER          LEDC_TIMER_0
#define LEDC_MODE           LEDC_LOW_SPEED_MODE
#define LEDC_CHANNEL        LEDC_CHANNEL_0
#define LEDC_DUTY_RES       LEDC_TIMER_8_BIT

// Логика направления вращения (1 или 0)
#define DIR_FORWARD_LEVEL   1
#define DIR_BACKWARD_LEVEL  0

// ==============================================================================

// MAC адрес пульта BT13 (ЗАМЕНИТЕ НА ВАШ, ЕСЛИ НУЖНО)
static esp_bd_addr_t bt13_addr = {0x8B, 0xEB, 0x75, 0x4E, 0x65, 0x97};

// Переменные управления двигателем
static int speed_level = 0;        
static bool motor_enabled = false; 
static bool long_press_active = false; 

// Настройки управления
static const int max_speed_level = 5;    
static const int pwm_per_level = 51;     // PWM на уровень (255/5 ≈ 51)

// Переменные для отслеживания длинных нажатий
static uint32_t long_press_start_time = 0;
static uint32_t last_long_press_event_time = 0;
static uint16_t long_press_button = 0;
static bool is_long_press_detected = false;

// Таймаут для определения реального отпускания длительного нажатия (мс)
#define LONG_PRESS_RELEASE_TIMEOUT_MS 200

// HID Usage коды для кнопок BT13
#define HID_USAGE_SHORT_PLUS    0x0004  
#define HID_USAGE_SHORT_MINUS   0x0008  
#define HID_USAGE_STOP          0x0010  
#define HID_USAGE_LONG_PLUS     0x0001  
#define HID_USAGE_LONG_MINUS    0x0002  

// HID Host переменные
static bool bt13_connected = false;
static bool restart_scan_needed = false;
static bool scanning_in_progress = false;

// Переменные для автоматической остановки мотора
static uint32_t disconnection_start_time = 0;
static const uint32_t MOTOR_STOP_TIMEOUT_MS = 10000; 

// Функции управления двигателем
static void motor_init(void);
static void motor_update_state(void);
static void print_motor_status(void);

// Функции обработки кнопок
static void short_press_plus(void);
static void short_press_minus(void);
static void start_long_press_plus(void);
static void start_long_press_minus(void);
static void end_long_press(void);
static void motor_stop_command(void);
static void motor_stop(void);
static void led_blink(int times, int delay_ms);

// Bluetooth функции
static void bt_gap_cb(esp_bt_gap_cb_event_t event, esp_bt_gap_cb_param_t *param);
static void hid_host_cb(void *handler_args, const char *event_name, int32_t event_id, void *param);
static void start_scan_for_bt13(void);
static void connection_monitor_task(void *pvParameters);

void app_main(void)
{
    esp_err_t ret;

    ESP_LOGI(TAG, "=== Universal ESP32 Motor Control ===");
    ESP_LOGI(TAG, "System initialization...");

    // Инициализация NVS
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Инициализация двигателя
    motor_init();
    ESP_LOGI(TAG, "Motor initialized with %d Hz PWM", LEDC_FREQUENCY);

    // Инициализация таймера отключения
    disconnection_start_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();

    ESP_LOGI(TAG, "Initializing BT controller...");
    ret = esp_bt_controller_init(&bt_cfg);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "BT controller init error: %s", esp_err_to_name(ret));
        return;
    }

    ESP_LOGI(TAG, "Enabling BT controller...");
    ret = esp_bt_controller_enable(ESP_BT_MODE_CLASSIC_BT);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "BT controller enable error: %s", esp_err_to_name(ret));
        return;
    }

    ESP_LOGI(TAG, "Initializing Bluedroid...");
    ret = esp_bluedroid_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Bluedroid init error: %s", esp_err_to_name(ret));
        return;
    }

    ESP_LOGI(TAG, "Enabling Bluedroid...");
    ret = esp_bluedroid_enable();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Bluedroid enable error: %s", esp_err_to_name(ret));
        return;
    }

    // Регистрация GAP callback
    ESP_ERROR_CHECK(esp_bt_gap_register_callback(bt_gap_cb));

    // Инициализация HID Host
    ESP_ERROR_CHECK(esp_hidh_init(&(esp_hidh_config_t){
        .callback = hid_host_cb,
        .event_stack_size = 4096,
        .callback_arg = NULL,
    }));

    ESP_LOGI(TAG, "Bluetooth initialized");
    ESP_LOGI(TAG, "Searching for BT13 remote...");

    // Начать поиск BT13
    start_scan_for_bt13();

    // Создать задачу мониторинга соединения
    xTaskCreate(connection_monitor_task, "connection_monitor", 2048, NULL, 5, NULL);

    // Основной цикл
    while (1) {
        if (is_long_press_detected && last_long_press_event_time > 0) {
            uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
            uint32_t time_since_last_event = current_time - last_long_press_event_time;
            
            if (time_since_last_event > LONG_PRESS_RELEASE_TIMEOUT_MS) {
                ESP_LOGI(TAG, "Long press timeout detected (%lu ms)", time_since_last_event);
                end_long_press();
                
                long_press_button = 0;
                is_long_press_detected = false;
                long_press_start_time = 0;
                last_long_press_event_time = 0;
            }
        }
        
        if (bt13_connected && motor_enabled) {
            led_blink(1, 100);
        } else if (bt13_connected) {
            led_blink(1, 500);
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

static void motor_init(void)
{
    ledc_timer_config_t ledc_timer = {
        .duty_resolution = LEDC_DUTY_RES,
        .freq_hz = LEDC_FREQUENCY,
        .speed_mode = LEDC_MODE,
        .timer_num = LEDC_TIMER,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&ledc_timer));

    ledc_channel_config_t ledc_channel = {
        .channel    = LEDC_CHANNEL,
        .duty       = 0,
        .gpio_num   = MOTOR_SPEED_PIN,
        .speed_mode = LEDC_MODE,
        .hpoint     = 0,
        .timer_sel  = LEDC_TIMER,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));

    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << MOTOR_DIR_PIN),
        .pull_down_en = 0,
        .pull_up_en = 0,
    };
    gpio_config(&io_conf);

    io_conf.pin_bit_mask = (1ULL << LED_PIN);
    gpio_config(&io_conf);

    motor_update_state();
    gpio_set_level(LED_PIN, 0);
}

static void motor_update_state(void)
{
    int actual_speed = 0;
    bool forward = true;

    if (motor_enabled && speed_level != 0) {
        actual_speed = abs(speed_level) * pwm_per_level;
        forward = (speed_level > 0);
    }

    ESP_ERROR_CHECK(ledc_set_duty(LEDC_MODE, LEDC_CHANNEL, actual_speed));
    ESP_ERROR_CHECK(ledc_update_duty(LEDC_MODE, LEDC_CHANNEL));
    
    gpio_set_level(MOTOR_DIR_PIN, forward ? DIR_FORWARD_LEVEL : DIR_BACKWARD_LEVEL);

    ESP_LOGI(TAG, "State: %s | Level: %d/%d | PWM: %d/255 | Direction: %s",
             motor_enabled ? "ON" : "OFF",
             speed_level, max_speed_level,
             actual_speed,
             forward ? "FORWARD" : "BACKWARD");
}

static void print_motor_status(void)
{
    if (!motor_enabled || speed_level == 0) {
        ESP_LOGI(TAG, "Stopped");
    } else {
        int percentage = (abs(speed_level) * 100) / max_speed_level;
        const char* direction = (speed_level > 0) ? "forward" : "backward";
        ESP_LOGI(TAG, "Running %s at %d%%", direction, percentage);
    }
}

static void short_press_plus(void)
{
    if (speed_level < max_speed_level) {
        speed_level++;
        motor_enabled = (speed_level != 0);
        motor_update_state();
        print_motor_status();
    }
}

static void short_press_minus(void)
{
    if (speed_level > -max_speed_level) {
        speed_level--;
        motor_enabled = (speed_level != 0);
        motor_update_state();
        print_motor_status();
    }
}

static void start_long_press_plus(void)
{
    if (!long_press_active) {
        long_press_active = true;
        speed_level = max_speed_level;
        motor_enabled = true;
        motor_update_state();
        print_motor_status();
    }
}

static void start_long_press_minus(void)
{
    if (!long_press_active) {
        long_press_active = true;
        speed_level = -max_speed_level;
        motor_enabled = true;
        motor_update_state();
        print_motor_status();
    }
}

static void end_long_press(void)
{
    if (long_press_active) {
        long_press_active = false;
        speed_level = 0;
        motor_enabled = false;
        motor_update_state();
        print_motor_status();
    }
}

static void motor_stop_command(void)
{
    long_press_active = false;
    speed_level = 0;
    motor_enabled = false;
    motor_update_state();
    print_motor_status();
}

static void motor_stop(void)
{
    speed_level = 0;
    motor_enabled = false;
    long_press_active = false;
    motor_update_state();
}

static void led_blink(int times, int delay_ms)
{
    for (int i = 0; i < times; i++) {
        gpio_set_level(LED_PIN, 1);
        vTaskDelay(pdMS_TO_TICKS(delay_ms));
        gpio_set_level(LED_PIN, 0);
        vTaskDelay(pdMS_TO_TICKS(delay_ms));
    }
}

static void start_scan_for_bt13(void)
{
    if (scanning_in_progress || bt13_connected) return;

    scanning_in_progress = true;
    esp_err_t ret = esp_bt_gap_start_discovery(ESP_BT_INQ_MODE_GENERAL_INQUIRY, 10, 0);
    if (ret != ESP_OK) scanning_in_progress = false;
}

static void bt_gap_cb(esp_bt_gap_cb_event_t event, esp_bt_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_BT_GAP_DISC_RES_EVT: {
        if (memcmp(param->disc_res.bda, bt13_addr, ESP_BD_ADDR_LEN) == 0) {
            esp_bt_gap_cancel_discovery();
            esp_hidh_dev_open(param->disc_res.bda, ESP_HID_TRANSPORT_BT, 0);
        }
        break;
    }
    case ESP_BT_GAP_DISC_STATE_CHANGED_EVT:
        if (param->disc_st_chg.state == ESP_BT_GAP_DISCOVERY_STOPPED) {
            scanning_in_progress = false;
        } else if (param->disc_st_chg.state == ESP_BT_GAP_DISCOVERY_STARTED) {
            scanning_in_progress = true;
        }
        break;
    default: break;
    }
}

static void hid_host_cb(void *handler_args, const char *event_name, int32_t event_id, void *param)
{
    switch (event_id) {
    case 0: 
        bt13_connected = true;
        disconnection_start_time = 0;
        led_blink(3, 200);
        break;

    case 1: 
    case 4: 
        bt13_connected = false;
        disconnection_start_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
        motor_stop();
        led_blink(5, 100);
        restart_scan_needed = true;
        break;

    case 2: 
        {
            esp_hidh_event_data_t *event_data = (esp_hidh_event_data_t *)param;
            if (event_data && event_data->input.data && event_data->input.length >= 2) {
                uint16_t usage = (event_data->input.data[1] << 8) | event_data->input.data[0];
                uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;
                bool pressed = (usage != 0);

                if (pressed) {
                    switch (usage) {
                        case HID_USAGE_SHORT_PLUS: short_press_plus(); break;
                        case HID_USAGE_SHORT_MINUS: short_press_minus(); break;
                        case HID_USAGE_STOP: motor_stop_command(); break;
                        case HID_USAGE_LONG_PLUS:
                            if (!is_long_press_detected || long_press_button != usage) {
                                long_press_button = usage;
                                long_press_start_time = current_time;
                                is_long_press_detected = true;
                                start_long_press_plus();
                            }
                            last_long_press_event_time = current_time;
                            break;
                        case HID_USAGE_LONG_MINUS:
                            if (!is_long_press_detected || long_press_button != usage) {
                                long_press_button = usage;
                                long_press_start_time = current_time;
                                is_long_press_detected = true;
                                start_long_press_minus();
                            }
                            last_long_press_event_time = current_time;
                            break;
                    }
                } else {
                    if (is_long_press_detected) {
                        uint32_t time_since_last_event = current_time - last_long_press_event_time;
                        if (time_since_last_event > LONG_PRESS_RELEASE_TIMEOUT_MS) {
                            end_long_press();
                            long_press_button = 0;
                            is_long_press_detected = false;
                            long_press_start_time = 0;
                            last_long_press_event_time = 0;
                        }
                    }
                }
            }
        }
        break;
    }
}

static void connection_monitor_task(void *pvParameters)
{
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(500));
        uint32_t current_time = xTaskGetTickCount() * portTICK_PERIOD_MS;

        if (!bt13_connected && disconnection_start_time > 0) {
            uint32_t disconnection_duration = current_time - disconnection_start_time;
            if (disconnection_duration >= MOTOR_STOP_TIMEOUT_MS) {
                if (motor_enabled || speed_level != 0) {
                    motor_stop();
                    led_blink(10, 100);
                }
                disconnection_start_time = 0;
            }
        }

        if (restart_scan_needed) {
            restart_scan_needed = false;
            vTaskDelay(pdMS_TO_TICKS(3000));
            if (!bt13_connected) start_scan_for_bt13();
        }

        static uint32_t last_connection_check = 0;
        if (!bt13_connected && (current_time - last_connection_check > 30000)) {
            start_scan_for_bt13();
            last_connection_check = current_time;
        }

        if (bt13_connected) last_connection_check = current_time;
    }
}
