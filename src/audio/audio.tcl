# audio.tcl - Critcl Audio Processing Utilities Package

package require critcl 3.1
package provide audio 1.0

# Namespace
namespace eval audio {}

########################
# C code for audio processing utilities
critcl::ccode {
#include <tcl.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static double calculate_rms_energy_16bit(const int16_t *samples, unsigned int num_samples) {
    if (num_samples == 0) return 0.0;

    long long sum_abs = 0;
    for (unsigned int i = 0; i < num_samples; i++) {
        int32_t sample = samples[i];
        sum_abs += (sample < 0) ? -sample : sample;  /* abs(sample) */
    }

    double mean_abs = (double)sum_abs / (double)num_samples;
    return (mean_abs / 32768.0) * 1000.0;  /* Normalize and scale like Python: mean(abs(samples)) * 1000 */
}

static double calculate_rms_energy_float32(const float *samples, unsigned int num_samples) {
    if (num_samples == 0) return 0.0;

    double sum_squares = 0.0;
    for (unsigned int i = 0; i < num_samples; i++) {
        double sample = samples[i];
        sum_squares += sample * sample;
    }

    double rms = sqrt(sum_squares / (double)num_samples);
    return rms * 100.0;  /* Convert to 0-100 scale */
}
}

critcl::cproc audio::energy {Tcl_Interp* interp Tcl_Obj* data_obj Tcl_Obj* format_obj} double {
    /* Get binary data */
    int data_len;
    unsigned char *data = Tcl_GetByteArrayFromObj(data_obj, &data_len);
    if (!data || data_len < 2) return 0.0;

    /* Get format string */
    const char *format = Tcl_GetString(format_obj);

    if (strcmp(format, "int16") == 0) {
        /* 16-bit signed integer format */
        unsigned int num_samples = data_len / 2;
        return calculate_rms_energy_16bit((const int16_t*)data, num_samples);
    } else if (strcmp(format, "float32") == 0) {
        /* 32-bit float format */
        unsigned int num_samples = data_len / 4;
        return calculate_rms_energy_float32((const float*)data, num_samples);
    } else {
        Tcl_SetResult(interp, "Unsupported format. Use 'int16' or 'float32'", TCL_STATIC);
        return 0.0;
    }
}

