CC = clang
CFLAGS = -fobjc-arc -O3 -Wall -Wextra
LDFLAGS = -framework Cocoa -framework IOKit -framework AudioToolbox

APP_NAME = LowWatt Handshake macOS
TARGET_BIN = $(APP_NAME)
APP_BUNDLE = $(APP_NAME).app
DMG_NAME = LowWatt-Handshake-macOS.dmg

all: $(APP_BUNDLE) $(DMG_NAME)

$(TARGET_BIN): menubar_app.m
	$(CC) $(CFLAGS) -o "$(TARGET_BIN)" menubar_app.m $(LDFLAGS)

$(APP_BUNDLE): $(TARGET_BIN)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(TARGET_BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(TARGET_BIN)"
	cp battery_connected_base.png "$(APP_BUNDLE)/Contents/Resources/"
	cp battery_disconnected_base.png "$(APP_BUNDLE)/Contents/Resources/"
	if [ -f "assets/battery_3d_icon.png" ]; then \
		cp assets/battery_3d_icon.png "$(APP_BUNDLE)/Contents/Resources/"; \
	fi

$(DMG_NAME): $(APP_BUNDLE)
	rm -rf dmg_root
	mkdir -p dmg_root
	cp -r "$(APP_BUNDLE)" dmg_root/
	hdiutil create -volname "$(APP_NAME)" -srcfolder dmg_root -ov -format UDZO "$(DMG_NAME)"
	rm -rf dmg_root

install: $(APP_BUNDLE)
	cp -r "$(APP_BUNDLE)" /Applications/
	cp com.siraj.lowwatthandshake.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.siraj.lowwatthandshake.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/com.siraj.lowwatthandshake.plist

clean:
	rm -f "$(TARGET_BIN)"
	rm -rf "$(APP_BUNDLE)"
	rm -f "$(DMG_NAME)"
	rm -rf dmg_root

.PHONY: all clean install
