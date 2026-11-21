// Existing MLX C binding: CPU graph, error channel and exact mapped libraries.
// No model, GPU work, native ownership/admission or installed operation.
#include <assert.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mlx/c/mlx.h"
static int errors;
static void on_error(const char *message, void *data) {
  (void)data;
  assert(message && message[0]);
  ++errors;
}
static void mapped(const char *expected) {
  char wanted[PATH_MAX], actual[PATH_MAX];
  assert(realpath(expected, wanted));
  int matches = 0;
  for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
    const char *name = _dyld_get_image_name(i);
    if (name && realpath(name, actual) && !strcmp(wanted, actual)) ++matches;
  }
  assert(matches == 1);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  mapped(argv[1]); mapped(argv[2]);
  mlx_set_error_handler(on_error, NULL, NULL);
  mlx_stream stream = mlx_default_cpu_stream_new();
  mlx_array a = mlx_array_new_float(3), b = mlx_array_new_float(4);
  mlx_array out = mlx_array_new(), invalid = mlx_array_new();
  assert(mlx_add(&out, a, b, stream) == 0);
  assert(mlx_array_eval(out) == 0);
  float value = 0;
  assert(mlx_array_item_float32(&value, out) == 0 && value == 7);
  const int shape[] = {2};
  assert(mlx_reshape(&invalid, a, shape, 1, stream) != 0);
  assert(errors == 1);
  assert(mlx_array_free(invalid) == 0);
  assert(mlx_array_free(out) == 0);
  assert(mlx_array_free(a) == 0 && mlx_array_free(b) == 0);
  assert(mlx_stream_free(stream) == 0);
  assert(errors == 1);
  puts("PASS actual MLX C CPU graph/error cleanup and mapped library identity; no native authority");
  return 0;
}
