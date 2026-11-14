#include "camera_smoothing.h"
#include <cstdio>
#include <cstdlib>
void check(bool ok){if(!ok){puts("smoothing check failed");exit(1);}}
bool near(float a,float b){return fabsf(a-b)<0.001f;}
Vec run(int fps){CameraSmoothing filter;Vec p{};Quat q=fromRot({0,0,0});filter.update(p,q,{},1.0f/fps,true,90);
 for(int i=0;i<fps;++i){p={4,0,0};q=fromRot({0,90,0});filter.update(p,q,{},1.0f/fps,true,90);}return {p.x,rotate(q,{1,0,0}).x,0};}
int main(){
 auto low=run(30),high=run(120);check(near(low.x,high.x)&&near(low.y,high.y));
 CameraSmoothing f;Vec p{};Quat q=fromRot({0,179,0});f.update(p,q,{},0.016f,true,90);
 p={};q=fromRot({0,-179,0});f.update(p,q,{},0.016f,true,90);check(rotate(q,{1,0,0}).x<-0.99f);
 p={100,0,0};q=fromRot({20,40,0});f.update(p,q,{100,0,0},0.016f,true,90);check(near(p.x,100));
 p={102,0,0};q=fromRot({20,40,0});f.update(p,q,{100,0,0},0.016f,true,90);check(p.x>100&&p.x<102);
 p={130,0,0};q=fromRot({0,90,0});f.update(p,q,{100,0,0},0.016f,false,90);check(near(p.x,130)&&near(rotate(q,{1,0,0}).y,1));
 p={1100,0,0};f.update(p,q,{1100,0,0},0.016f,true,90);check(near(p.x,1100));
 p={1200,0,0};f.update(p,q,{1100,0,0},0.016f,true,90);check(p.x>=1194);
 p={1300,0,0};f.update(p,q,{1100,0,0},0.016f,true,0);check(near(p.x,1300));
 puts("PASS: framerate independence, shortest rotation, pawn travel, filtering, toggle, teleport, leash, zero time");
}
