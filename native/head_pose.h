#pragma once
#include <cmath>
struct Vec {float x,y,z;};
struct Quat {float x,y,z,w;};
inline Vec rotate(Quat q,Vec v) {
    Vec t{2*(q.y*v.z-q.z*v.y),2*(q.z*v.x-q.x*v.z),2*(q.x*v.y-q.y*v.x)};
    return {v.x+q.w*t.x+q.y*t.z-q.z*t.y,v.y+q.w*t.y+q.z*t.x-q.x*t.z,v.z+q.w*t.z+q.x*t.y-q.y*t.x};
}
inline Quat mul(Quat a,Quat b) {return {a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z};}
inline Quat fromRot(Vec r) {
    const float k=3.14159265359f/360;
    Quat yaw{0,0,sinf(r.y*k),cosf(r.y*k)},pitch{0,-sinf(r.x*k),0,cosf(r.x*k)},roll{-sinf(r.z*k),0,0,cosf(r.z*k)};
    return mul(mul(yaw,pitch),roll);
}
inline Quat inverse(Quat q){float n=q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w;return {-q.x/n,-q.y/n,-q.z/n,q.w/n};}
inline bool valid(Quat q){float n=q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w;return std::isfinite(n)&&n>0.9f&&n<1.1f;}
