VOC = /opt/voc/bin/voc

all:
	$(VOC) -Fs System/Objects.Mod
	$(VOC) -Fs System/Display.Mod
	$(VOC) -Fs Images/Colors.Mod
	$(VOC) -Fs Images/Images.Mod
