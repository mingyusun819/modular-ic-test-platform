/* NUCLEO-G474RE communication test firmware.
 * PA2/PA3 LPUART1 -> onboard ST-LINK virtual COM port (factory solder bridges).
 * Measurement values are SIMULATED; this file does not drive DUT hardware.
 */
#include "stm32g4xx_hal.h"
#include "platform_protocol.h"
#include <stdio.h>

#ifndef PLATFORM_UART_BAUD
#define PLATFORM_UART_BAUD 115200u
#endif

#define RX_RING_SIZE 1024u
static UART_HandleTypeDef serial;
static ADC_HandleTypeDef supply_adc;
static bool supply_adc_ready;
static PlatformProtocol protocol;
static uint8_t rx_byte;
static volatile uint8_t rx_ring[RX_RING_SIZE];
static volatile uint16_t rx_head, rx_tail;
static volatile bool rx_lost;

static void fatal_error(void)
{
    __disable_irq();
    for (;;) {
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        for (volatile uint32_t delay = 0; delay < 500000u; ++delay) __NOP();
    }
}

static void clock_init(void)
{
    __HAL_RCC_PWR_CLK_ENABLE();
    if (HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1) != HAL_OK)
        fatal_error();

    RCC_OscInitTypeDef oscillator = {0};
    oscillator.OscillatorType = RCC_OSCILLATORTYPE_HSI;
    oscillator.HSIState = RCC_HSI_ON;
    oscillator.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
    oscillator.PLL.PLLState = RCC_PLL_NONE;
    if (HAL_RCC_OscConfig(&oscillator) != HAL_OK) fatal_error();

    RCC_ClkInitTypeDef clock = {0};
    clock.ClockType = RCC_CLOCKTYPE_SYSCLK | RCC_CLOCKTYPE_HCLK |
                      RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clock.SYSCLKSource = RCC_SYSCLKSOURCE_HSI;
    clock.AHBCLKDivider = RCC_SYSCLK_DIV1;
    clock.APB1CLKDivider = RCC_HCLK_DIV1;
    clock.APB2CLKDivider = RCC_HCLK_DIV1;
    if (HAL_RCC_ClockConfig(&clock, FLASH_LATENCY_0) != HAL_OK) fatal_error();

    RCC_PeriphCLKInitTypeDef peripheral = {0};
    peripheral.PeriphClockSelection = RCC_PERIPHCLK_LPUART1;
    peripheral.Lpuart1ClockSelection = RCC_LPUART1CLKSOURCE_PCLK1;
    if (HAL_RCCEx_PeriphCLKConfig(&peripheral) != HAL_OK) fatal_error();
}

static void led_init(void)
{
    __HAL_RCC_GPIOA_CLK_ENABLE();
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin = GPIO_PIN_5;
    gpio.Mode = GPIO_MODE_OUTPUT_PP;
    gpio.Pull = GPIO_NOPULL;
    gpio.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(GPIOA, &gpio);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_RESET);
}

void HAL_UART_MspInit(UART_HandleTypeDef *uart)
{
    if (uart->Instance != LPUART1) return;
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_LPUART1_CLK_ENABLE();
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin = GPIO_PIN_2 | GPIO_PIN_3;
    gpio.Mode = GPIO_MODE_AF_PP;
    gpio.Pull = GPIO_NOPULL;
    gpio.Speed = GPIO_SPEED_FREQ_LOW;
    gpio.Alternate = GPIO_AF12_LPUART1;
    HAL_GPIO_Init(GPIOA, &gpio);
    HAL_NVIC_SetPriority(LPUART1_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(LPUART1_IRQn);
}

static void serial_init(void)
{
    serial.Instance = LPUART1;
    serial.Init.BaudRate = PLATFORM_UART_BAUD;
    serial.Init.WordLength = UART_WORDLENGTH_8B;
    serial.Init.StopBits = UART_STOPBITS_1;
    serial.Init.Parity = UART_PARITY_NONE;
    serial.Init.Mode = UART_MODE_TX_RX;
    serial.Init.HwFlowCtl = UART_HWCONTROL_NONE;
    serial.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
    serial.Init.ClockPrescaler = UART_PRESCALER_DIV1;
    serial.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
    if (HAL_UART_Init(&serial) != HAL_OK) fatal_error();
    if (HAL_UARTEx_DisableFifoMode(&serial) != HAL_OK) fatal_error();
    if (HAL_UART_Receive_IT(&serial, &rx_byte, 1) != HAL_OK) fatal_error();
}

static bool serial_write(void *context, const char *text, size_t length)
{
    (void)context;
    /* Interrupts remain enabled during TX; incoming commands enter the ring. */
    return HAL_UART_Transmit(&serial, (uint8_t *)text, (uint16_t)length, 100) == HAL_OK;
}

static void supply_init(void)
{
    __HAL_RCC_ADC12_CLK_ENABLE();
    supply_adc.Instance = ADC1;
    supply_adc.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV2;
    supply_adc.Init.Resolution = ADC_RESOLUTION_12B;
    supply_adc.Init.DataAlign = ADC_DATAALIGN_RIGHT;
    supply_adc.Init.ScanConvMode = ADC_SCAN_DISABLE;
    supply_adc.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
    supply_adc.Init.NbrOfConversion = 1;
    supply_adc.Init.ExternalTrigConv = ADC_SOFTWARE_START;
    supply_adc.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
    supply_adc.Init.Overrun = ADC_OVR_DATA_PRESERVED;
    if (HAL_ADC_Init(&supply_adc) != HAL_OK) return;
    if (HAL_ADCEx_Calibration_Start(&supply_adc, ADC_SINGLE_ENDED) != HAL_OK) return;
    ADC_ChannelConfTypeDef channel = {0};
    channel.Channel = ADC_CHANNEL_VREFINT;
    channel.Rank = ADC_REGULAR_RANK_1;
    channel.SamplingTime = ADC_SAMPLETIME_640CYCLES_5;
    channel.SingleDiff = ADC_SINGLE_ENDED;
    channel.OffsetNumber = ADC_OFFSET_NONE;
    if (HAL_ADC_ConfigChannel(&supply_adc, &channel) != HAL_OK) return;
    HAL_Delay(1); /* Allow the internal reference to settle. */
    supply_adc_ready = true;
}

static void supply_report(void)
{
    uint32_t sum = 0;
    bool valid = supply_adc_ready;
    for (unsigned i = 0; valid && i < 16; ++i) {
        if (HAL_ADC_Start(&supply_adc) != HAL_OK ||
            HAL_ADC_PollForConversion(&supply_adc, 2) != HAL_OK) {
            valid = false;
        } else {
            sum += HAL_ADC_GetValue(&supply_adc);
        }
        if (HAL_ADC_Stop(&supply_adc) != HAL_OK) valid = false;
    }
    uint32_t raw = (sum + 8u) / 16u;
    uint32_t calibration = *VREFINT_CAL_ADDR;
    char message[64];
    if (valid && raw != 0 && calibration != 0 && calibration != 0xffffu) {
        /* Estimates VREF+/VDDA when the board ties VREF+ to VDDA. */
        uint32_t mv = __HAL_ADC_CALC_VREFANALOG_VOLTAGE(raw, ADC_RESOLUTION_12B);
        if (mv >= 1620u && mv <= 3600u) {
            int length = snprintf(message, sizeof(message), "STATUS,VDDA_MV,%lu\n",
                                  (unsigned long)mv);
            (void)serial_write(NULL, message, (size_t)length);
            return;
        }
    }
    const char error[] = "STATUS,VDDA_MV,UNAVAILABLE\n";
    (void)serial_write(NULL, error, sizeof(error) - 1u);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *uart)
{
    if (uart->Instance != LPUART1) return;
    uint16_t next = (uint16_t)((rx_head + 1u) % RX_RING_SIZE);
    if (next == rx_tail) {
        rx_lost = true;
    } else {
        rx_ring[rx_head] = rx_byte;
        rx_head = next;
    }
    if (HAL_UART_Receive_IT(uart, &rx_byte, 1) != HAL_OK) rx_lost = true;
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *uart)
{
    if (uart->Instance == LPUART1) rx_lost = true;
    /* Main re-arms a stopped receiver after the HAL interrupt handler returns. */
}

void LPUART1_IRQHandler(void) { HAL_UART_IRQHandler(&serial); }
void SysTick_Handler(void) { HAL_IncTick(); }

int main(void)
{
    HAL_Init();
    led_init();
    clock_init();
    serial_init();
    supply_init();
    platform_init(&protocol, serial_write, NULL, PLATFORM_UART_BAUD);
    uint32_t next_supply_ms = HAL_GetTick();

    for (;;) {
        /* Bound each batch so a continuous byte stream cannot starve telemetry. */
        for (unsigned budget = 0; budget < RX_RING_SIZE; ++budget) {
            uint32_t interrupt_state = __get_PRIMASK();
            __disable_irq();
            bool lost = rx_lost;
            rx_lost = false;
            if (lost) rx_tail = rx_head;
            if (serial.RxState == HAL_UART_STATE_READY &&
                HAL_UART_Receive_IT(&serial, &rx_byte, 1) != HAL_OK) {
                rx_lost = true;
            }
            bool available = rx_tail != rx_head;
            uint8_t byte = 0;
            if (available) {
                byte = rx_ring[rx_tail];
                rx_tail = (uint16_t)((rx_tail + 1u) % RX_RING_SIZE);
            }
            __set_PRIMASK(interrupt_state);
            if (lost) platform_rx_lost(&protocol);
            if (!available) break;
            platform_feed(&protocol, byte, HAL_GetTick());
        }
        platform_poll(&protocol, HAL_GetTick());
        uint32_t now = HAL_GetTick();
        if ((int32_t)(now - next_supply_ms) >= 0) {
            supply_report();
            next_supply_ms = HAL_GetTick() + 1000u;
        }
        HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5,
                          protocol.streaming ? GPIO_PIN_SET : GPIO_PIN_RESET);
        /* 1 ms SysTick and UART RX both wake the CPU. */
        __WFI();
    }
}
