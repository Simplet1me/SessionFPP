// Based on the verified SessionOpenMP camera API. GPL-3.0-or-later.
#include <windows.h>
#include <Xinput.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>
#include <filesystem>
#include <share.h>
#include "ue_access.h"
#include "MinHook.h"
#include "settings.h"
#include "head_pose.h"
#include "camera_smoothing.h"
using RC::Unreal::UObject;
namespace {
FILE* logfile=nullptr;
void log(const char* s) {if(logfile){fprintf(logfile,"%s\n",s);fflush(logfile);}}
template<class T> T& at(void* p,size_t off) {return *reinterpret_cast<T*>(static_cast<unsigned char*>(p)+off);}
using Tick=void(*)(void*,float);
using SetTransform=void(*)(void*,const float*,const float*,bool,void*,unsigned char);
Tick original=nullptr; SetTransform setTransform=nullptr; void* hook=nullptr;
bool down=false,fault=false;
CameraSmoothing smoothing;
void* smoothingPawn=nullptr;void* smoothingComponent=nullptr;
// Unique executable-section matches only. Ambiguous/updated builds fail closed.
void* scan(const char* pattern) {
    std::vector<int> bytes; const char* p=pattern;
    while(*p){if(*p==' '){++p;continue;} if(*p=='?'){bytes.push_back(-1);while(*p=='?')++p;}else{char* end=nullptr;bytes.push_back(static_cast<int>(strtoul(p,&end,16)));p=end;}}
    auto base=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
    auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(base+reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
    auto sections=IMAGE_FIRST_SECTION(nt); void* result=nullptr;
    for(unsigned s=0;s<nt->FileHeader.NumberOfSections;++s){
        if(!(sections[s].Characteristics&IMAGE_SCN_MEM_EXECUTE))continue;
        auto start=base+sections[s].VirtualAddress; size_t size=sections[s].Misc.VirtualSize;
        for(size_t i=0;i+bytes.size()<=size;++i){bool match=true;for(size_t j=0;j<bytes.size();++j)if(bytes[j]>=0&&start[i+j]!=bytes[j]){match=false;break;}
            if(match){if(result)return nullptr;result=start+i;}}
    } return result;
}
// Measured SessionOpenMP skeletal API: mesh +0x280, final ref skeleton at +0x1b0,
// double-buffered component-space pose at +0x4b0, read buffer index +0x4f4.
using NameToString=void(*)(const void*,void*);
NameToString nameToString=nullptr;
struct Transform {Quat rotation;Vec position;float pad;Vec scale;float pad2;};
static_assert(sizeof(Transform)==48);
struct BoneInfo {unsigned long long name;int parent;};
// Ref bone info is packed to 12 bytes in UE4; access with byte strides below.
struct Array {unsigned char* data;int count,capacity;};
bool headView(UObject* pawn,Vec& position,Quat& rotation){
    auto mesh=at<void*>(pawn,0x280);if(!mesh || !nameToString)return false;
    auto skeleton=at<void*>(mesh,0x480);if(!skeleton)return false;
    auto info=at<Array>(skeleton,0x1d0);auto reference=at<Array>(skeleton,0x1e0);
    if(!info.data || !reference.data || info.count<=0 || info.count>512 || reference.count!=info.count)return false;
    static void* lastMesh=nullptr;static void* lastSkeleton=nullptr;static int head=-1,count=0;static Quat correction{};
    if(mesh!=lastMesh || skeleton!=lastSkeleton || count!=info.count){
        lastMesh=mesh;lastSkeleton=skeleton;count=info.count;head=-1;
        for(int i=0;i<count;++i){
            // Supply a bounded reusable FString buffer; ordinary bone names fit without engine allocation.
            wchar_t buffer[1024]{};struct String {wchar_t* data;int count,capacity;} name{buffer,0,1024};
            nameToString(info.data+i*12,&name);
            if(!name.data || name.count<=0 || name.count>1024)continue;
            if(_wcsicmp(name.data,L"head")==0 || _wcsicmp(name.data,L"amxx_head")==0){head=i;break;}
        }
        if(head<0){log("No head/amxx_head bone found on current skeleton");return false;}
        // Bone axes are rig axes, not camera axes. A CONSTANT reference-pose correction
        // aligns them once; it never estimates animated look direction or cancels head turns.
        Quat rest{0,0,0,1};int bone=head,depth=0;
        while(bone>=0 && depth++<count){
            if(bone>=count)return false;
            auto q=reinterpret_cast<Transform*>(reference.data)[bone].rotation;if(!valid(q))return false;
            rest=mul(q,rest);int parent=at<int>(info.data,bone*12+8);
            if(parent>=bone)return false;bone=parent;
        }
        auto meshRelative=fromRot(at<Vec>(mesh,0x128));
        correction=mul(inverse(rest),inverse(meshRelative));
        log("Resolved animated head bone; camera follows position and complete rotation");
    }
    if(head<0)return false;
    int read=at<int>(mesh,0x4f4);if(read!=0&&read!=1)return false;
    auto pose=at<Array>(mesh,0x4b0+read*0x10);if(!pose.data||pose.count!=count)return false;
    auto bone=reinterpret_cast<Transform*>(pose.data)[head];auto world=at<Transform>(mesh,0x1c0);
    if(!valid(bone.rotation)||!valid(world.rotation))return false;
    auto offset=rotate(world.rotation,{bone.position.x*world.scale.x,bone.position.y*world.scale.y,bone.position.z*world.scale.z});
    position={world.position.x+offset.x,world.position.y+offset.y,world.position.z+offset.z};
    rotation=mul(mul(world.rotation,bone.rotation),correction);
    return valid(rotation)&&std::isfinite(position.x)&&std::isfinite(position.y)&&std::isfinite(position.z);
}
struct Saved {void* component=nullptr;void* actor=nullptr;Vec location{},rotation{};float fov=0;bool wrote=false;} saved;

// Log transitions only, so a failed guard is visible without per-frame log spam.
void state(const char* message) {static std::string previous;if(previous!=message){log(message);previous=message;}}
bool focused(){DWORD pid=0;GetWindowThreadProcessId(GetForegroundWindow(),&pid);return pid==GetCurrentProcessId();}
void restore(void* camera) {
    if(!saved.wrote)return;
    // Called only on the currently ticking camera; never dereference a cached actor after travel.
    if(saved.actor==camera && at<void*>(camera,0x228)==saved.component){
        auto root=at<void*>(camera,0x130);if(root){auto q=at<Quat>(root,0x1c0);auto pos=at<Vec>(root,0x1d0);auto off=rotate(q,saved.location);Vec p{pos.x+off.x,pos.y+off.y,pos.z+off.z};auto rot=mul(q,fromRot(saved.rotation));
            setTransform(saved.component,&p.x,&rot.x,false,nullptr,0);at<float>(saved.component,0x1f8)=saved.fov;}
    } saved={};
}
bool frame(void* camera,float dt) {
    bool held=(GetAsyncKeyState('G')&0x8000)!=0;
    // Aggregate keyboard and all XInput slots into a single rising edge.
    // Disconnected slots are retried once a second, supporting hot-plug without busy polling.
    static ULONGLONG retry[XUSER_MAX_COUNT]{};const auto now=GetTickCount64();
    for(DWORD user=0;user<XUSER_MAX_COUNT;++user){
        if(now<retry[user])continue;
        XINPUT_STATE pad{};
        if(XInputGetState(user,&pad)==ERROR_SUCCESS){retry[user]=0;held=held || (pad.Gamepad.wButtons&XINPUT_GAMEPAD_RIGHT_SHOULDER)!=0;}
        else retry[user]=now+1000;
    }
    if(focused()&&held&&!down){toggleFirstPerson();log(firstPersonEnabled()?"G/RB: first person requested":"G/RB: third person");}down=held;
    auto component=at<void*>(camera,0x228);
    if(saved.actor!=camera || saved.component!=component)saved={};
    if(!firstPersonEnabled() || !focused()){state(firstPersonEnabled()?"WAIT: game window not focused":"VIEW: third person");restore(camera);return false;}
    // Resolve possession each frame. FindFirstOf(SkaterCharacter) would select remote/replay actors.
    auto pc=RC::Unreal::UObjectGlobals::FindFirstOf(L"PlayerController");
    if(!pc){state("WAIT: no PlayerController");restore(camera);return false;}
    // Same possession source as SessionOpenMP: AController::Pawn, confirmed by K2_GetPawn.
    // AcknowledgedPawn is network acknowledgement state, not the possession authority.
    auto pawn=at<UObject*>(pc,0x250);
    if(!pawn || !component){state("WAIT: no possessed Pawn or camera component");restore(camera);return false;}
    auto local=pawn->GetFunctionByNameInChain(L"IsLocallyControlled");
    if(!local || local->GetParmsSize()!=1){state("BLOCKED: IsLocallyControlled API unavailable");restore(camera);return false;}
    bool ours=false;pawn->ProcessEvent(local,&ours);
    if(!ours){state("WAIT: possessed Pawn is not locally controlled");restore(camera);return false;}
    // GetViewTarget is exposed by APlayerController. Do not look it up on PlayerCameraManager.
    auto getTarget=pc->GetFunctionByNameInChain(L"GetViewTarget");
    UObject* viewTarget=nullptr;
    if(!getTarget || getTarget->GetParmsSize()!=sizeof(UObject*)){state("BLOCKED: PlayerController.GetViewTarget API unavailable");restore(camera);return false;}
    pc->ProcessEvent(getTarget,&viewTarget);
    if(viewTarget!=reinterpret_cast<UObject*>(camera) && viewTarget!=pawn){state("WAIT: replay/editor or different camera owns the view target");restore(camera);return false;}
    if(at<unsigned char>(pawn,0x710)&2){state("WAIT: skater is ragdolling");restore(camera);return false;}
    Vec headPosition{};Quat headRotation{};
    if(!headView(pawn,headPosition,headRotation)){state("WAIT: animated head bone pose unavailable");restore(camera);return false;}
    if(!saved.wrote){saved={component,camera,at<Vec>(component,0x11c),at<Vec>(component,0x128),at<float>(component,0x1f8),true};}
    // Fixed eye offsets in the head's own frame. All animated yaw, pitch and roll pass through.
    auto offset=rotate(headRotation,{cameraForward(),cameraSide(),cameraUp()});
    Vec position{headPosition.x+offset.x,headPosition.y+offset.y,headPosition.z+offset.z};
    // Post-multiply: the adjustment stays local to the animated head.
    auto rotation=mul(headRotation,fromRot({cameraPitch(),cameraYaw(),cameraRoll()}));
    auto pawnRoot=at<void*>(pawn,0x130);
    if(!pawnRoot){restore(camera);return false;}
    if(smoothingPawn!=pawn||smoothingComponent!=component){smoothing.reset();smoothingPawn=pawn;smoothingComponent=component;}
    smoothing.update(position,rotation,at<Vec>(pawnRoot,0x1d0),dt,cameraSmoothingEnabled(),cameraSmoothingMs());
    setTransform(component,&position.x,&rotation.x,false,nullptr,0);at<float>(component,0x1f8)=cameraFov();
    state("VIEW: first person following animated head bone");
    return true;
}
void guardedFrame(void* camera,float dt){__try{if(!frame(camera,dt))smoothing.reset();}__except(EXCEPTION_EXECUTE_HANDLER){fault=true;smoothing.reset();disableFirstPerson();log("Memory/API fault: first person disabled for this session");__try{restore(camera);}__except(EXCEPTION_EXECUTE_HANDLER){saved={};}}}
void beforeTick(void* self){__try{restore(self);}__except(EXCEPTION_EXECUTE_HANDLER){saved={};fault=true;log("Restore fault: first person disabled");}}
void tick(void* self,float dt){beforeTick(self);original(self,dt);if(!fault)try{guardedFrame(self,dt);}catch(...){disableFirstPerson();log("C++ API error; view returned to third person");restore(self);}}
}
class FirstPerson final:public RC::CppUserModBase {
public:
    FirstPerson(){ModName=L"SessionFPP";ModVersion=L"0.3.1";ModDescription=L"G or controller RB toggles first and third person";ModAuthors=L"SessionFPP";
        wchar_t exe[32768]{};GetModuleFileNameW(nullptr,exe,32768);auto root=std::filesystem::path(exe).parent_path();logfile=_wfsopen((root/L"SessionFPP.log").c_str(),L"w",_SH_DENYNO);
        initializeSettings((root/L"SessionFPP.ini").c_str());
    }
    void on_update() override {registerSettingsMenu();}
    void on_unreal_init() override {
        hook=scan("40 55 57 48 8D AC 24 18 FC FF FF 48 81 EC E8 04 00 00 44 0F 29 8C 24 80 04 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 60 03 00 00");
        setTransform=reinterpret_cast<SetTransform>(scan("4C 8B DC 53 55 56 57 41 56 48 81 EC C0 00 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 80 00 00 00"));
        nameToString=reinterpret_cast<NameToString>(scan("48 89 5C 24 18 48 89 74 24 20 57 48 83 EC 30 8B 01 48 8B F1 8B F8 48 8B DA C1 EF 10 83 79 04 00"));
        if(!hook||!setTransform||!nameToString){log("Unsupported game build: camera signatures missing or ambiguous; no hooks installed");hook=nullptr;return;}
        auto status=MH_Initialize();if(status!=MH_OK&&status!=MH_ERROR_ALREADY_INITIALIZED){log("MinHook initialization failed");hook=nullptr;return;}
        if(MH_CreateHook(hook,reinterpret_cast<void*>(tick),reinterpret_cast<void**>(&original))!=MH_OK){log("Camera hook creation failed");hook=nullptr;return;}
        if(MH_EnableHook(hook)!=MH_OK){MH_RemoveHook(hook);hook=nullptr;log("Camera hook enable failed");return;}
        log("SessionFPP 0.3.1 ready. Press G or controller RB in gameplay. Default: third person.");
    }
    ~FirstPerson() override {if(hook){MH_DisableHook(hook);MH_RemoveHook(hook);}if(logfile){fclose(logfile);logfile=nullptr;}}
};
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod(){return new FirstPerson();}
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod){delete mod;}
