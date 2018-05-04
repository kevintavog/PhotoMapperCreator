# In case I don't remember these commands...

build:
	swift build

release-build:
	swift build -c release -Xswiftc -static-stdlib

update:
	swift package update

push:
	scp .build/release/PhotoMapCreator tavog@yuba.local:PhotoMapper/
