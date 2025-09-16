# uinput.tcl - Tcl uinput wrapper using critcl

package require critcl

# Configure critcl
critcl::cflags -DUINPUT_MAX_NAME_SIZE=80

# Namespace
namespace eval uinput {}

# Package information
package provide uinput 1.0

# C code for uinput functionality
critcl::ccode {
    #include <linux/uinput.h>
    #include <linux/input.h>
    #include <fcntl.h>
    #include <unistd.h>
    #include <string.h>
    #include <sys/ioctl.h>
    #include <errno.h>

    typedef struct {
        int fd;
        int initialized;
    } UInputDevice;

    static UInputDevice device = {-1, 0};

    static void emit_event(int type, int code, int value) {
        struct input_event ie;
        ie.type = type;
        ie.code = code;
        ie.value = value;
        ie.time.tv_sec = 0;
        ie.time.tv_usec = 0;
        write(device.fd, &ie, sizeof(ie));
    }

    static void emit_sync() {
        emit_event(EV_SYN, SYN_REPORT, 0);
    }

    static void emit_key_click(int key) {
        emit_event(EV_KEY, key, 1);  // key down
        emit_sync();
        usleep(10000);  // 10ms delay
        emit_event(EV_KEY, key, 0);  // key up
        emit_sync();
    }

    static void emit_key_combo(int modifier, int key) {
        emit_event(EV_KEY, modifier, 1);  // modifier down
        emit_sync();
        usleep(5000);
        emit_event(EV_KEY, key, 1);       // key down
        emit_sync();
        usleep(5000);
        emit_event(EV_KEY, key, 0);       // key up
        emit_sync();
        usleep(5000);
        emit_event(EV_KEY, modifier, 0);  // modifier up
        emit_sync();
    }

    static int setup_key_events() {
        // Enable key events
        if (ioctl(device.fd, UI_SET_EVBIT, EV_KEY) < 0) return -1;

        // Enable all the keys we use - exact key codes
        int keys[] = {
            // Letters: a-z
            30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44,
            // Numbers: 0-9
            11, 2, 3, 4, 5, 6, 7, 8, 9, 10,
            // Special keys
            57, 28, 42, 12, 13, 26, 27, 43, 39, 40, 41, 51, 52, 53
        };

        for (int i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
            if (ioctl(device.fd, UI_SET_KEYBIT, keys[i]) < 0) return -1;
        }

        return 0;
    }

    // Initialize uinput device
    static int uinput_init_device() {
        if (device.initialized) return 0;

        device.fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
        if (device.fd < 0) return -1;

        struct uinput_user_dev uidev;
        memset(&uidev, 0, sizeof(uidev));
        snprintf(uidev.name, UINPUT_MAX_NAME_SIZE, "Tcl Virtual Keyboard");
        uidev.id.bustype = BUS_USB;
        uidev.id.vendor = 0x1234;
        uidev.id.product = 0x5678;
        uidev.id.version = 1;

        if (setup_key_events() < 0) {
            close(device.fd);
            device.fd = -1;
            return -1;
        }

        if (write(device.fd, &uidev, sizeof(uidev)) < 0) {
            close(device.fd);
            device.fd = -1;
            return -1;
        }

        if (ioctl(device.fd, UI_DEV_CREATE) < 0) {
            close(device.fd);
            device.fd = -1;
            return -1;
        }

        device.initialized = 1;
        return 0;
    }

    // Character to key mapping - using exact Linux input key codes
    static int char_to_key(char c) {
        switch (c) {
            // Letters (lowercase)
            case 'a': return 30;  case 'b': return 48;  case 'c': return 46;  case 'd': return 32;
            case 'e': return 18;  case 'f': return 33;  case 'g': return 34;  case 'h': return 35;
            case 'i': return 23;  case 'j': return 36;  case 'k': return 37;  case 'l': return 38;
            case 'm': return 50;  case 'n': return 49;  case 'o': return 24;  case 'p': return 25;
            case 'q': return 16;  case 'r': return 19;  case 's': return 31;  case 't': return 20;
            case 'u': return 22;  case 'v': return 47;  case 'w': return 17;  case 'x': return 45;
            case 'y': return 21;  case 'z': return 44;

            // Numbers
            case '0': return 11;  case '1': return 2;   case '2': return 3;   case '3': return 4;
            case '4': return 5;   case '5': return 6;   case '6': return 7;   case '7': return 8;
            case '8': return 9;   case '9': return 10;

            // Punctuation and symbols
            case ' ': return 57;  case '-': return 12;  case '=': return 13;  case '[': return 26;
            case ']': return 27;  case '\\': return 43; case ';': return 39;  case '\'': return 40;
            case '`': return 41;  case ',': return 51;  case '.': return 52;  case '/': return 53;

            default: return -1;   // Unsupported character
        }
    }

    // Type a single character - using correct key mappings
    static void uinput_type_char(char c) {
        if (!device.initialized) return;

        // Handle uppercase letters (shift + letter)
        if (c >= 'A' && c <= 'Z') {
            int key = char_to_key(c + 32); // Convert to lowercase and get key
            if (key >= 0) {
                emit_key_combo(42, key); // 42 = KEY_LEFTSHIFT
            }
        }
        // Handle special characters requiring shift
        else if (c == '!') emit_key_combo(42, 2);   // KEY_1
        else if (c == '@') emit_key_combo(42, 3);   // KEY_2
        else if (c == '#') emit_key_combo(42, 4);   // KEY_3
        else if (c == '$') emit_key_combo(42, 5);   // KEY_4
        else if (c == '%') emit_key_combo(42, 6);   // KEY_5
        else if (c == '^') emit_key_combo(42, 7);   // KEY_6
        else if (c == '&') emit_key_combo(42, 8);   // KEY_7
        else if (c == '*') emit_key_combo(42, 9);   // KEY_8
        else if (c == '(') emit_key_combo(42, 10);  // KEY_9
        else if (c == ')') emit_key_combo(42, 11);  // KEY_0
        else if (c == '_') emit_key_combo(42, 12);  // KEY_MINUS
        else if (c == '+') emit_key_combo(42, 13);  // KEY_EQUAL
        else if (c == '{') emit_key_combo(42, 26);  // KEY_LEFTBRACE
        else if (c == '}') emit_key_combo(42, 27);  // KEY_RIGHTBRACE
        else if (c == '|') emit_key_combo(42, 43);  // KEY_BACKSLASH
        else if (c == ':') emit_key_combo(42, 39);  // KEY_SEMICOLON
        else if (c == '"') emit_key_combo(42, 40);  // KEY_APOSTROPHE
        else if (c == '<') emit_key_combo(42, 51);  // KEY_COMMA
        else if (c == '>') emit_key_combo(42, 52);  // KEY_DOT
        else if (c == '?') emit_key_combo(42, 53);  // KEY_SLASH
        else if (c == '~') emit_key_combo(42, 41);  // KEY_GRAVE
        // Handle newline
        else if (c == '\n') emit_key_click(28);     // KEY_ENTER
        // Handle other characters
        else {
            int key = char_to_key(c);
            if (key >= 0) {
                emit_key_click(key);
            }
        }

        usleep(10000);  // Small delay between characters
    }

    // Type a string
    static void uinput_type_string(const char *str) {
        if (!device.initialized || !str) return;

        for (int i = 0; str[i]; i++) {
            uinput_type_char(str[i]);
        }
    }

    // Cleanup uinput device
    static void uinput_cleanup_device() {
        if (device.initialized && device.fd >= 0) {
            ioctl(device.fd, UI_DEV_DESTROY);
            close(device.fd);
            device.fd = -1;
            device.initialized = 0;
        }
    }
}

# Simple wrapper functions using critcl::cproc
critcl::cproc uinput::init {} int {
    return uinput_init_device();
}

critcl::cproc uinput::type {char* text} void {
    uinput_type_string(text);
}

critcl::cproc uinput::cleanup {} void {
    uinput_cleanup_device();
}