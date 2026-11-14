#pragma once
// Native pause-menu guest integration, using SessionOpenMP's public C ABI.
void registerSettingsMenu();
void initializeSettings(const wchar_t* ini);
bool firstPersonEnabled();
void toggleFirstPerson();
void disableFirstPerson();
float cameraFov();
float cameraForward();
float cameraUp();


float cameraSide();
float cameraPitch();
float cameraYaw();
float cameraRoll();

bool cameraSmoothingEnabled();
float cameraSmoothingMs();
