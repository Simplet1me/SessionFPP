#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include "menu_ext.h"
#include "settings.h"
namespace {
// Values and callbacks are game-thread owned. on_update only discovers/registers the page.
bool enabled=false;
std::wstring iniPath;
struct Setting {const char* key;const wchar_t* iniKey;float value,initial,low,high;};
Setting values[]={
    {"FOV",L"FOV",110,110,60,140},
    {"EyeForwardCm",L"EyeForwardCm",18,18,-100,100},
    {"EyeSideCm",L"EyeSideCm",0,0,-100,100},
    {"EyeUpCm",L"EyeUpCm",0,0,-100,100},
    {"RotationPitchDeg",L"RotationPitchDeg",0,0,-180,180},
    {"RotationYawDeg",L"RotationYawDeg",0,0,-180,180},
    {"RotationRollDeg",L"RotationRollDeg",0,0,-180,180},
    {"SmoothingEnabled",L"SmoothingEnabled",1,1,0,1},
    {"SmoothingMs",L"SmoothingMs",90,90,0,300}
};
void save(){
    for(const auto& v:values){wchar_t text[32]{};swprintf_s(text,L"%.3f",v.value);if(!WritePrivateProfileStringW(L"Camera",v.iniKey,text,iniPath.c_str()))OutputDebugStringW(L"SessionFPP: failed to save camera setting\n");}
}
void select(const char* key,void*){if(strcmp(key,"Reset")==0){for(auto& v:values)v.value=v.initial;save();}}
void change(const char* key,int iv,float fv,void*){
    if(strcmp(key,"Enabled")==0){enabled=iv!=0;return;}
    if(strcmp(key,"SmoothingEnabled")==0){values[7].value=iv!=0?1.0f:0.0f;save();return;}
    for(auto& v:values)if(strcmp(key,v.key)==0){if(std::isfinite(fv)){v.value=std::clamp(fv,v.low,v.high);save();}return;}
}
int get(const char* key,int* iv,float* fv,void*){
    if(strcmp(key,"Enabled")==0){*iv=enabled?1:0;return 1;}
    if(strcmp(key,"SmoothingEnabled")==0){*iv=values[7].value!=0?1:0;return 1;}
    for(const auto& v:values)if(strcmp(key,v.key)==0){*fv=v.value;return 1;}
    return 0;
}
const OmpPageItem2 rows[]={
    {OMP_ITEM_TOGGLE,"Enabled","First person","G or controller RB toggles first and third person during gameplay.","Off","On",0,0,0},
    {OMP_ITEM_SLIDER,"FOV","Field of view (deg)","Horizontal field of view. Saved automatically.",nullptr,nullptr,60,140,1},
    {OMP_ITEM_SLIDER,"EyeForwardCm","Position X - forward (cm)","Head-local X offset; positive moves forward.",nullptr,nullptr,-100,100,1},
    {OMP_ITEM_SLIDER,"EyeSideCm","Position Y - right (cm)","Head-local Y offset; positive moves right.",nullptr,nullptr,-100,100,1},
    {OMP_ITEM_SLIDER,"EyeUpCm","Position Z - up (cm)","Head-local Z offset; positive moves up.",nullptr,nullptr,-100,100,1},
    {OMP_ITEM_SLIDER,"RotationPitchDeg","Rotation Y - pitch (deg)","Local pitch offset; positive looks up.",nullptr,nullptr,-180,180,1},
    {OMP_ITEM_SLIDER,"RotationYawDeg","Rotation Z - yaw (deg)","Local yaw offset; positive turns right.",nullptr,nullptr,-180,180,1},
    {OMP_ITEM_SLIDER,"RotationRollDeg","Rotation X - roll (deg)","Local roll offset; positive tilts right.",nullptr,nullptr,-180,180,1},
    {OMP_ITEM_TOGGLE,"SmoothingEnabled","Camera smoothing","Smooth head position and rotation. Off follows the head directly.","Off","On",0,0,0},
    {OMP_ITEM_SLIDER,"SmoothingMs","Smoothing time (ms)","Higher reduces shake but delays head turns. Zero follows directly.",nullptr,nullptr,0,300,5},
    {OMP_ITEM_ACTION,"Reset","Reset camera settings","Restore FOV 110, position (18, 0, 0) cm zero rotation offsets, smoothing on at 90 ms.",nullptr,nullptr,0,0,0}
};
}
void initializeSettings(const wchar_t* ini){
    iniPath=ini;
    for(auto& v:values){wchar_t text[64]{};auto def=std::to_wstring(v.initial);GetPrivateProfileStringW(L"Camera",v.iniKey,def.c_str(),text,64,ini);
        wchar_t* end=nullptr;float n=wcstof(text,&end);v.value=(end!=text && *end==0 && std::isfinite(n) && n>=v.low && n<=v.high)?n:v.initial;}
}
void registerSettingsMenu(){
    static bool registered=false;static ULONGLONG next=0;auto now=GetTickCount64();if(registered||now<next)return;next=now+2000;
    HMODULE modules[1024]{};DWORD needed=0;if(!EnumProcessModules(GetCurrentProcess(),modules,sizeof(modules),&needed))return;
    using Register=int(*)(const char*,const OmpPageItem2*,int,OmpPageSelectFn,OmpPageValueFn,OmpPageGetFn,OmpPageStatusFn,void*);
    for(size_t i=0;i<std::min<size_t>(needed/sizeof(HMODULE),1024);++i){
        auto reg=reinterpret_cast<Register>(GetProcAddress(modules[i],"OmpMenu_RegisterPage2"));
        if(reg && reg("SessionFPP",rows,static_cast<int>(std::size(rows)),select,change,get,nullptr,nullptr)){registered=true;OutputDebugStringW(L"SessionFPP: native pause-menu settings registered\n");return;}
    }
}
bool firstPersonEnabled(){return enabled;}
void toggleFirstPerson(){enabled=!enabled;}
void disableFirstPerson(){enabled=false;}
float cameraFov(){return values[0].value;}
float cameraForward(){return values[1].value;}
float cameraSide(){return values[2].value;}
float cameraUp(){return values[3].value;}
float cameraPitch(){return values[4].value;}
float cameraYaw(){return values[5].value;}
float cameraRoll(){return values[6].value;}


bool cameraSmoothingEnabled(){return values[7].value!=0;}
float cameraSmoothingMs(){return values[8].value;}
