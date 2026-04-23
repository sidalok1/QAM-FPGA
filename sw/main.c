#ifndef __MICROBLAZE__
#define __MICROBLAZE__
#endif

#include <xil_assert.h>
#include "xparameters.h"
#include "mb_interface.h"
#include "xil_types.h"
#include "xuartlite.h"
#include "xuartlite_l.h"
#include "xstatus.h"
#include "xintc_l.h"
#include "xintc.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include <string.h>

XUartLite uart;
static XIntc interrupt_controller;
XIntc *intc = &interrupt_controller;

#define RADIO_FSL_ID 0
#define MAX_BYTES 128
#define MSR_FSL_BIT 0x10

#define RADIO_INT_ID 0

u8 uart_recv_buf[MAX_BYTES];
u8 uart_recv_idx = 0;
int uart_empty = TRUE;
u8 radio_recv_buf[MAX_BYTES];
u8 radio_recv_idx = 0;

int init();
// Source code comments say I need to add this attribute, though I'm not sure how necessary this is,
// as I cannot find example code using fast interrupts
void read_from_uart() __attribute__ ((fast_interrupt)); // must check why interrupt was signalled
void read_from_radio() __attribute__ ((fast_interrupt));
void send_over_radio();
void send_over_uart();

int main() {
    int status;
    if ((status = init()) != XST_SUCCESS) return status;
    while (1) send_over_uart();
}


int init() {
    int status;
    

    // Initialize interrupt controller
    status = XIntc_Initialize(intc, XPAR_XINTC_0_BASEADDR);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // Interrupt controller self test
    status = XIntc_SelfTest(intc);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // Connect the interrupt handlers to the interrupt controller
    // - Connect radio rx interrupt handler
    status = XIntc_ConnectFastHandler(intc, XPAR_FABRIC_AXI_UARTLITE_0_INTR, (XFastInterruptHandler) read_from_uart);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // - Connect uart rx interrupt handler (custom, not supplied by uart driver)
    status = XIntc_ConnectFastHandler(intc, RADIO_INT_ID, (XFastInterruptHandler) read_from_radio);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // Initialize uart
    status = XUartLite_Initialize(&uart, XPAR_AXI_UARTLITE_0_BASEADDR);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // Uart self test
    status = XUartLite_SelfTest(&uart);
    if (status != XST_SUCCESS) return XST_FAILURE;
    // Enable exceptions. I'm not really sure if this is needed. I think using fast interrupt handlers it is not, but
    // I can't find any example code using fast interrupts.
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler) XIntc_DeviceInterruptHandler, (void *)0);
    Xil_ExceptionEnable();

    print("Done with startup\n");
    strcpy((char*)uart_recv_buf, "init\n");
    uart_recv_idx = 4;
    uart_empty = FALSE;
    send_over_radio();
    
    
    // Enable interrupts
    XIntc_Enable(intc, XPAR_FABRIC_AXI_UARTLITE_0_INTR);
    XUartLite_EnableInterrupt(&uart);
    XIntc_Enable(intc, RADIO_INT_ID);

    
    // Start interrupt handling
    return XIntc_Start(intc, XIN_REAL_MODE);

}

void read_from_uart() {
    // According to the MicroBlaze documentation, the MicroBlaze itself will automatically
    // disable and enable (all) interrupts

    // while there is data to be received over uart
    while (!XUartLite_IsReceiveEmpty(XPAR_AXI_UARTLITE_0_BASEADDR)) {
        // read a byte from the uart fifo
        u8 byte = XUartLite_ReadReg(XPAR_AXI_UARTLITE_0_BASEADDR, XUL_RX_FIFO_OFFSET);
        switch (byte) {
        case '\010': // backspace
            uart_recv_idx--;
            break;
        case '\r':
        case '\n': // enter
            uart_recv_buf[uart_recv_idx] = byte;
            send_over_radio(); // may set uart_empty = TRUE
            break;
        default: // all other characters considered valid (as of now)
            uart_recv_buf[uart_recv_idx++] = byte;
            uart_empty = FALSE;
            break;
        }
    }
    // It is possible for this handler to be called when the uart tx fifo is empty, regardless
    // of whether or not the uart rx fifo contains data.
    // Because the main loop already handles sending data over uart, no need to call it here
    return;
}

void send_over_uart() {
    u8 idx = 0;
    while (idx != radio_recv_idx) {
        XUartLite_SendByte(XPAR_XUARTLITE_0_BASEADDR, radio_recv_buf[idx++]);
    }
    radio_recv_idx = 0;
}

void read_from_radio() {
    u32 w, s; // data word, and status register
    u8 c; // data byte
    // Only called if radio requests an interrupt, which should only happen
    // if there is data to be received. Moreover, interrupts will not be requested again,
    // so reads should happen in blocking mode
    do {
        // place stream link data into word
        getfsl(w, RADIO_FSL_ID);
        // extract least significant byte
        c = w & 0xFF;
        // add to the radio receive buffer
        radio_recv_buf[radio_recv_idx++] = c;
        // will be set if tlast is asserted
        fsl_iserror(s);
    } while (!s);
    msrclr(MSR_FSL_BIT);
}

void send_over_radio() {
    u8 c;
    u32 w;
    u8 i;
    if (uart_empty) return;
    for ( i = 0; i < uart_recv_idx; i++ ) {
        c = uart_recv_buf[i];
        w = c & 0xFF;
        putfsl(w, RADIO_FSL_ID);
    }
    c = uart_recv_buf[i];
    w = c &0xFF;
    cputfsl(w, RADIO_FSL_ID);
    uart_recv_idx = 0;
    uart_empty = TRUE;
}