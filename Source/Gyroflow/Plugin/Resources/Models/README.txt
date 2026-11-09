GMFlow / UniMatch model for Gyroflow Toolbox

Model: gmflow-scale2-regrefine6.bpk
Source: https://api.gyroflow.xyz/sdk/gmflow-scale2-regrefine6.bpk
SHA-256: 8d51cb8eaf2c56b6f727ef83534616c4dd98f4ce7ff9b5fa812c132c44db9db7
Upstream model: https://github.com/autonomousvision/unimatch

The model is bundled for offline use and validated by unmodified Gyroflow Core before loading.
Inference uses Metal through Core's Burn/WGPU backend. Toolbox selects hardware GPUs only.
The renderer supplies the bundled weights path before starting FxPlug, which prevents Core from
entering its download branch. Compiled kernels are cached in the renderer's sandbox container.

The model attribution is in LICENSE.txt. Burn and CubeCL license notices accompany it in Notices.
