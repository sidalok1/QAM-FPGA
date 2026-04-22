#include "xparameters.h"
#include "mb_interface.h"
#include "xil_types.h"
#include "xuartlite.h"
#include "xil_printf.h"
#include "xstatus.h"
#include <string.h>

XUartLite UartLite;

#define RADIO_FSL_ID 0
#define MAX_BYTES 2048
#define MSR_FSL_BIT 0x10

u8 uart_recv_buf[MAX_BYTES];
unsigned int uart_recv_idx = 0;
u8 radio_recv_buf[MAX_BYTES];
unsigned int radio_recv_idx = 0;

int init_sys();
void shd_sys();
void send_over_radio();
int send_over_uart();
int radio_recv();

int main() {
    int status;
    if ( (status = init_sys()) != XST_SUCCESS ) return status;
    print("Done with startup\n");
    strcpy((char*)uart_recv_buf, "init\n");
    uart_recv_idx = 4;
    send_over_radio();
    while (1) {
        if ( XUartLite_Recv(&UartLite, uart_recv_buf + uart_recv_idx, 1) == 1 ) {
            switch ( uart_recv_buf[uart_recv_idx] ) {
            case '\010':
                uart_recv_idx--;
            break;
            case '\r':
            case '\n':
                send_over_radio();
            break;
            default:
                uart_recv_idx++;
            break;
            }
        }
        if ( (status = radio_recv()) != XST_SUCCESS ) return status;
    }

    shd_sys();

    return XST_SUCCESS;
}

int radio_recv() {
    u32 w, s;
    u8 c;
    ngetfsl(w, RADIO_FSL_ID);
    fsl_isinvalid(s);
    while ( !s ) {
        c = w & 0xFF;
        radio_recv_buf[radio_recv_idx++] = c;
        fsl_iserror(s); // indicates control (tlast asserted)
        if ( s ) {
            msrclr(MSR_FSL_BIT);
            return send_over_uart();
        }
        ngetfsl(w, RADIO_FSL_ID);
        fsl_isinvalid(s);
    }
    return XST_SUCCESS;
}

void send_over_radio() {
    u8 c;
    u32 w;
    unsigned int i;
    for ( i = 0; i < uart_recv_idx; i++ ) {
        c = uart_recv_buf[i];
        w = c & 0xFF;
        putfsl(w, RADIO_FSL_ID);
    }
    c = uart_recv_buf[i];
    w = c &0xFF;
    cputfsl(w, RADIO_FSL_ID);
    uart_recv_idx = 0;
}

int send_over_uart() {
    if ( XUartLite_Send(&UartLite, radio_recv_buf, radio_recv_idx) != radio_recv_idx )
        return XST_SEND_ERROR;
    radio_recv_idx = 0;
    return XST_SUCCESS;
}

int init_sys() {
    int status;
    microblaze_enable_dcache();
    microblaze_enable_icache();
    status = XUartLite_Initialize(&UartLite, XPAR_AXI_UARTLITE_0_BASEADDR);
    status |= XUartLite_SelfTest(&UartLite);
    if ( status != XST_SUCCESS ) {
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

void shd_sys() {
    microblaze_disable_dcache();
    microblaze_disable_icache();
}