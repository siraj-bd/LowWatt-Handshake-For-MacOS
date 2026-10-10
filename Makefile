CC = clang
CFLAGS = -fobjc-arc -O3 -arch arm64 -arch x86_64 -Wall -Wextra -fvisibility=hidden -fno-ident
LDFLAGS = -Wl,-dead_strip -framework Cocoa -framework IOKit -framework AudioToolbox

APP_NAME = LowWatt Handshake macOS
TARGET_BIN = "LowWatt Handshake macOS"
APP_BUNDLE = "LowWatt Handshake macOS.app"
DMG_NAME = LowWatt-Handshake-macOS.dmg

all: app dmg

app: menubar_app.m security_obfuscation.h Info.plist
	$(CC) $(CFLAGS) -o $(TARGET_BIN) menubar_app.m $(LDFLAGS)
	strip -x $(TARGET_BIN)
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(TARGET_BIN) $(APP_BUNDLE)/Contents/MacOS/$(TARGET_BIN)
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp battery_connected_base.png $(APP_BUNDLE)/Contents/Resources/
	cp battery_disconnected_base.png $(APP_BUNDLE)/Contents/Resources/
	cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true

dmg: app
	rm -rf dmg_root $(DMG_NAME)
	mkdir -p dmg_root
	cp -r $(APP_BUNDLE) dmg_root/
	hdiutil create -volname "$(APP_NAME)" -srcfolder dmg_root -ov -format UDZO "$(DMG_NAME)"
	rm -rf dmg_root

install: app
	cp -r $(APP_BUNDLE) /Applications/
	cp com.siraj.lowwatthandshake.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.siraj.lowwatthandshake.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/com.siraj.lowwatthandshake.plist

clean:
	rm -f $(TARGET_BIN)
	rm -rf $(APP_BUNDLE)
	rm -f $(DMG_NAME)
	rm -rf dmg_root

.PHONY: all app dmg clean install
