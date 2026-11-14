#pragma once
#include <algorithm>
#include "head_pose.h"
inline Quat slerpShortest(Quat a,Quat b,float t){
    float dot=a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w;
    if(dot<0){b={-b.x,-b.y,-b.z,-b.w};dot=-dot;}
    dot=std::clamp(dot,0.0f,1.0f);float x=1-t,y=t;
    if(dot<0.9995f){float angle=acosf(dot),den=sinf(angle);x=sinf((1-t)*angle)/den;y=sinf(t*angle)/den;}
    Quat q{x*a.x+y*b.x,x*a.y+y*b.y,x*a.z+y*b.z,x*a.w+y*b.w};
    float n=sqrtf(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);return {q.x/n,q.y/n,q.z/n,q.w/n};
}
struct CameraSmoothing {
    bool ready=false;Vec relative{},lastAnchor{};Quat orientation{};
    void reset(){ready=false;}
    void update(Vec& position,Quat& rotation,Vec anchor,float dt,bool enabled,float milliseconds){
        Vec target{position.x-anchor.x,position.y-anchor.y,position.z-anchor.z};
        Vec travel{anchor.x-lastAnchor.x,anchor.y-lastAnchor.y,anchor.z-lastAnchor.z};
        bool snap=!ready||!enabled||!std::isfinite(dt)||dt<=0||dt>0.25f||milliseconds<=0||
            travel.x*travel.x+travel.y*travel.y+travel.z*travel.z>250000;
        lastAnchor=anchor;
        if(snap){relative=target;orientation=rotation;ready=enabled;return;}
        float alpha=-expm1f(-0.69314718056f*dt/(milliseconds*0.001f));
        relative={relative.x+(target.x-relative.x)*alpha,relative.y+(target.y-relative.y)*alpha,relative.z+(target.z-relative.z)*alpha};
        // Smooth head bob relative to the moving pawn, not its movement through the map.
        // Limit eye lag to 6 cm so the filtered eye does not remain deep inside the body.
        Vec delta{relative.x-target.x,relative.y-target.y,relative.z-target.z};
        float distance=sqrtf(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z);
        if(distance>6){float k=6/distance;relative={target.x+delta.x*k,target.y+delta.y*k,target.z+delta.z*k};}
        orientation=slerpShortest(orientation,rotation,alpha);
        position={anchor.x+relative.x,anchor.y+relative.y,anchor.z+relative.z};rotation=orientation;
    }
};
