#include <windows.h>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <limits>
#include <string>
#include "menu_ext.h"
#include "settings.h"
namespace { OmpPageSelectFn selectRow=nullptr;OmpPageValueFn setValue=nullptr;OmpPageGetFn getValue=nullptr;int registered=0;
void check(bool ok){if(!ok){fputs("settings verification failed\n",stderr);ExitProcess(1);}}
}
extern "C" __declspec(dllexport) int OmpMenu_RegisterPage2(const char* title,const OmpPageItem2* rows,int count,OmpPageSelectFn select,OmpPageValueFn value,OmpPageGetFn get,OmpPageStatusFn,void*){
    check(std::string(title)=="SessionFPP" && count==11);check(rows[1].kind==OMP_ITEM_SLIDER && rows[1].minValue==60 && rows[1].maxValue==140);
    selectRow=select;setValue=value;getValue=get;++registered;return 1;
}
int main(){
    auto path=std::filesystem::current_path()/L"settings-check.ini";
    check(!std::filesystem::exists(path));initializeSettings(path.c_str());check(cameraFov()==110 && !firstPersonEnabled());
    registerSettingsMenu();registerSettingsMenu();check(registered==1 && setValue && getValue && selectRow);
    setValue("Enabled",1,0,nullptr);int iv=0;float fv=0;check(firstPersonEnabled());check(getValue("Enabled",&iv,&fv,nullptr)==1 && iv==1);
    toggleFirstPerson();check(!firstPersonEnabled());
    check(cameraSmoothingEnabled() && cameraSmoothingMs()==90);
    setValue("SmoothingEnabled",0,0,nullptr);setValue("SmoothingMs",0,150,nullptr);
    initializeSettings(path.c_str());check(!cameraSmoothingEnabled() && cameraSmoothingMs()==150);
    check(getValue("SmoothingEnabled",&iv,&fv,nullptr)==1 && iv==0);
    setValue("FOV",0,125,nullptr);setValue("EyeForwardCm",0,24,nullptr);setValue("EyeUpCm",0,-8,nullptr);setValue("EyeSideCm",0,12,nullptr);
    setValue("RotationPitchDeg",0,-25,nullptr);setValue("RotationYawDeg",0,40,nullptr);setValue("RotationRollDeg",0,15,nullptr);
    initializeSettings(path.c_str());check(cameraFov()==125 && cameraForward()==24 && cameraUp()==-8 && cameraSide()==12 && cameraPitch()==-25 && cameraYaw()==40 && cameraRoll()==15);
    setValue("FOV",0,200,nullptr);check(cameraFov()==140);setValue("FOV",0,std::numeric_limits<float>::quiet_NaN(),nullptr);check(cameraFov()==140);
    check(getValue("FOV",&iv,&fv,nullptr)==1 && fv==140);check(getValue("unknown",&iv,&fv,nullptr)==0);
    selectRow("Reset",nullptr);initializeSettings(path.c_str());check(cameraFov()==110 && cameraForward()==18 && cameraUp()==0 && cameraSide()==0 && cameraPitch()==0 && cameraYaw()==0 && cameraRoll()==0);
    check(cameraSmoothingEnabled() && cameraSmoothingMs()==90);
    std::filesystem::remove(path);puts("PASS: native page registration, toggle, seven sliders, bounds, NaN, persistence, reset");
}
