# audio.tcl - Critcl Audio Processing Utilities Package
# High-performance audio signal processing functions

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

/* Calculate mean absolute value energy from 16-bit PCM audio data (Python-compatible) */
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

/* Calculate RMS energy from float32 PCM audio data */
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

########################
# Tcl commands

# audio::energy - Calculate RMS energy from audio data
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

# audio::peak - Find peak amplitude in audio data
critcl::cproc audio::peak {Tcl_Interp* interp Tcl_Obj* data_obj Tcl_Obj* format_obj} double {
    /* Get binary data */
    int data_len;
    unsigned char *data = Tcl_GetByteArrayFromObj(data_obj, &data_len);
    if (!data || data_len < 2) return 0.0;

    /* Get format string */
    const char *format = Tcl_GetString(format_obj);

    if (strcmp(format, "int16") == 0) {
        /* 16-bit signed integer format */
        unsigned int num_samples = data_len / 2;
        const int16_t *samples = (const int16_t*)data;

        int16_t peak = 0;
        for (unsigned int i = 0; i < num_samples; i++) {
            int16_t abs_sample = (samples[i] < 0) ? -samples[i] : samples[i];
            if (abs_sample > peak) peak = abs_sample;
        }

        return (peak / 32768.0) * 100.0;  /* Convert to 0-100 scale */
    } else if (strcmp(format, "float32") == 0) {
        /* 32-bit float format */
        unsigned int num_samples = data_len / 4;
        const float *samples = (const float*)data;

        float peak = 0.0f;
        for (unsigned int i = 0; i < num_samples; i++) {
            float abs_sample = (samples[i] < 0) ? -samples[i] : samples[i];
            if (abs_sample > peak) peak = abs_sample;
        }

        return peak * 100.0;  /* Convert to 0-100 scale */
    } else {
        Tcl_SetResult(interp, "Unsupported format. Use 'int16' or 'float32'", TCL_STATIC);
        return 0.0;
    }
}

# audio::analyze - Get comprehensive audio analysis (energy, peak, etc.)
critcl::cproc audio::analyze {Tcl_Interp* interp Tcl_Obj* data_obj Tcl_Obj* format_obj} Tcl_Obj* {
    /* Get binary data */
    int data_len;
    unsigned char *data = Tcl_GetByteArrayFromObj(data_obj, &data_len);
    if (!data || data_len < 2) {
        return Tcl_NewDictObj();
    }

    /* Get format string */
    const char *format = Tcl_GetString(format_obj);

    double energy = 0.0;
    double peak = 0.0;
    unsigned int num_samples = 0;

    if (strcmp(format, "int16") == 0) {
        /* 16-bit signed integer format */
        num_samples = data_len / 2;
        const int16_t *samples = (const int16_t*)data;

        /* Calculate energy and peak in one pass */
        long long sum_squares = 0;
        int16_t max_abs = 0;

        for (unsigned int i = 0; i < num_samples; i++) {
            int32_t sample = samples[i];
            sum_squares += (long long)(sample * sample);

            int16_t abs_sample = (sample < 0) ? -sample : sample;
            if (abs_sample > max_abs) max_abs = abs_sample;
        }

        if (num_samples > 0) {
            double rms = sqrt((double)sum_squares / (double)num_samples);
            energy = (rms / 32768.0) * 100.0;
        }
        peak = (max_abs / 32768.0) * 100.0;

    } else if (strcmp(format, "float32") == 0) {
        /* 32-bit float format */
        num_samples = data_len / 4;
        const float *samples = (const float*)data;

        /* Calculate energy and peak in one pass */
        double sum_squares = 0.0;
        float max_abs = 0.0f;

        for (unsigned int i = 0; i < num_samples; i++) {
            double sample = samples[i];
            sum_squares += sample * sample;

            float abs_sample = (samples[i] < 0) ? -samples[i] : samples[i];
            if (abs_sample > max_abs) max_abs = abs_sample;
        }

        if (num_samples > 0) {
            double rms = sqrt(sum_squares / (double)num_samples);
            energy = rms * 100.0;
        }
        peak = max_abs * 100.0;
    } else {
        /* Unsupported format */
        Tcl_SetResult(interp, "Unsupported format. Use 'int16' or 'float32'", TCL_STATIC);
        return NULL;
    }

    /* Build result list instead of dictionary for safety */
    Tcl_Obj *result = Tcl_NewListObj(0, NULL);

    /* Add energy */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj("energy", -1));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewDoubleObj(energy));

    /* Add peak */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj("peak", -1));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewDoubleObj(peak));

    /* Add samples */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj("samples", -1));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(num_samples));

    /* Add format */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj("format", -1));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj(format, -1));

    return result;
}

########################
# Tcl wrapper functions with default parameters

# Wrapper for energy with default format
proc audio::energy_default {data {format "int16"}} {
    return [audio::energy $data $format]
}

# Wrapper for peak with default format
proc audio::peak_default {data {format "int16"}} {
    return [audio::peak $data $format]
}

# Wrapper for analyze with default format
proc audio::analyze_default {data {format "int16"}} {
    return [audio::analyze $data $format]
}

# Package metadata
# Package already provided at top