# Requis par flutter_onnxruntime (cf. doc du plugin) : sans ces règles,
# R8 casse les bindings Java d'ONNX Runtime en build release.
-keep class ai.onnxruntime.** { *; }
