#pragma once

// #ifdef __cplusplus
// extern "C"
// {
// #endif /* __cplusplus */

void exactinit();

float orient2d(float pa[2], float pb[2], float pc[2]);
float orient3d(float pa[3], float pb[3], float pc[3], float pd[3]);
float incircle(float pa[2], float pb[2], float pc[2], float pd[2]);
float insphere(float pa[3], float pb[3], float pc[3], float pd[3], float pe[3]);

// #ifdef __cplusplus
// }
// #endif /* __cplusplus */
