#include "head_pose.h"
#include <cstdio>
#include <cstdlib>
void check(bool ok){if(!ok){puts("head rotation check failed");exit(1);}}
bool near(float a,float b){return fabsf(a-b)<0.0001f;}
int main(){
    // An animated 90-degree head turn must look sideways, regardless of chase-camera yaw.
    auto turned=rotate(fromRot({0,90,0}),{1,0,0});check(near(turned.x,0)&&near(turned.y,1));
    // Looking at the board follows the head's pitch rather than a fixed camera pitch.
    auto down=rotate(fromRot({-60,0,0}),{1,0,0});check(near(down.x,0.5f)&&near(down.z,-0.8660254f));
    // Rig-axis correction is fixed: neutral becomes forward, animated head delta survives.
    auto bind=fromRot({0,90,0});auto animated=mul(fromRot({-60,0,0}),bind);
    auto corrected=mul(animated,inverse(bind));auto view=rotate(corrected,{1,0,0});check(near(view.x,down.x)&&near(view.z,down.z));
    // Head-local eye-up offset must roll with the head, not remain world vertical.
    auto up=rotate(fromRot({0,0,90}),{0,0,1});check(near(up.y,1)&&near(up.z,0));
    check(!valid({0,0,0,0}));puts("PASS: head turn, look down, rig alignment, rolled eye offset");
}
