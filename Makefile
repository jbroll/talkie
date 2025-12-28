
all: build

build:
	$(MAKE) -C src build

clean:
	$(MAKE) -C src clean

# Install uinput-perms runit service (Void Linux)
install-uinput-service:
	sudo cp -r etc/sv/uinput-perms /etc/sv/
	sudo ln -sf /etc/sv/uinput-perms /var/service/
	@echo "uinput-perms service installed and enabled"

# Quick fix: set uinput permissions now
fix-uinput:
	sudo chgrp input /dev/uinput
	sudo chmod 660 /dev/uinput
	@echo "/dev/uinput permissions fixed"
