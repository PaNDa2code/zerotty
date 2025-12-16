#include <Python.h>
#include <stdio.h>

int main() {
  const char* file_name = "zt_ast.py";
  Py_Initialize();
  FILE *fp = fopen(file_name, "r");
  if (!fp) {
    perror("fopen");
    Py_Finalize();
    return -1;
  }

  PyRun_SimpleFile(fp, file_name);

  fclose(fp);
  Py_Finalize();
  return 0;
}
