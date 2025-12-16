import ast

source = ""

with open("plugin.py") as file:
    source += file.read()

tree = ast.parse(source)

class Optimizer(ast.NodeTransformer):
    def visit_If(self, node):
        if isinstance(node.test, ast.Constant) and node.test.value is False:
            return None
        return node


tree = Optimizer().visit(tree)
ast.fix_missing_locations(tree)

code = compile(tree, "plugin.py", "exec")

exec(code, {})
