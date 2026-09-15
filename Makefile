ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VMLSpeedBubble VMLRuntimeSniffer CarPlayWeatherIPC CarPlayTemplateHostProbe WeatherSpeechBridge CarPlayVisibilityGuard YouTubeBubbleSignal CarPlayHostBubbleFix

VMLSpeedBubble_FILES = Tweak.xm
VMLSpeedBubble_CFLAGS = -fobjc-arc -Werror
VMLSpeedBubble_FRAMEWORKS = UIKit Foundation QuartzCore

VMLRuntimeSniffer_FILES = RuntimeSniffer.xm
VMLRuntimeSniffer_CFLAGS = -fobjc-arc -Werror
VMLRuntimeSniffer_FRAMEWORKS = UIKit Foundation
VMLRuntimeSniffer_LIBRARIES = substrate

CarPlayWeatherIPC_FILES = CarPlayWeatherIPC.xm
CarPlayWeatherIPC_CFLAGS = -fobjc-arc -Werror
CarPlayWeatherIPC_FRAMEWORKS = UIKit Foundation QuartzCore
CarPlayWeatherIPC_LIBRARIES = substrate

CarPlayTemplateHostProbe_FILES = CarPlayTemplateHostProbe.xm
CarPlayTemplateHostProbe_CFLAGS = -fobjc-arc -Werror
CarPlayTemplateHostProbe_FRAMEWORKS = UIKit Foundation QuartzCore CoreLocation
CarPlayTemplateHostProbe_LIBRARIES = substrate

WeatherSpeechBridge_FILES = WeatherSpeechBridge.xm
WeatherSpeechBridge_CFLAGS = -fobjc-arc -Werror
WeatherSpeechBridge_FRAMEWORKS = Foundation AVFoundation
WeatherSpeechBridge_LIBRARIES = substrate

CarPlayVisibilityGuard_FILES = CarPlayVisibilityGuard.xm
CarPlayVisibilityGuard_CFLAGS = -fobjc-arc -Werror
CarPlayVisibilityGuard_FRAMEWORKS = UIKit Foundation QuartzCore
CarPlayVisibilityGuard_LIBRARIES = substrate

YouTubeBubbleSignal_FILES = YouTubeBubbleSignal.xm
YouTubeBubbleSignal_CFLAGS = -fobjc-arc -Werror
YouTubeBubbleSignal_FRAMEWORKS = UIKit Foundation
YouTubeBubbleSignal_LIBRARIES = substrate

CarPlayHostBubbleFix_FILES = CarPlayHostBubbleFix.xm
CarPlayHostBubbleFix_CFLAGS = -fobjc-arc -Werror
CarPlayHostBubbleFix_FRAMEWORKS = UIKit Foundation QuartzCore
CarPlayHostBubbleFix_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
