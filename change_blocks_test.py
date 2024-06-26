#!/bin/env python3
#
import unittest
from change_blocks import parse_blocks, apply_changes

class TestChangeBlocks(unittest.TestCase):

    def setUp(self):
        self.maxDiff = None

    def test_parse_blocks(self):
        content = """In the beginning

# @block1
content of block1

def function1():
    pass

# @block2
content of block2

# @run
if __name__ == "__main__":
    main()
"""
        expected = {
            'HEADER': 'In the beginning',
            'block1': '# @block1\ncontent of block1',
            'function1': 'def function1():\n    pass',
            'block2': '# @block2\ncontent of block2',
            'run': '# @run\nif __name__ == "__main__":\n    main()'
        }
        self.assertEqual(parse_blocks(content), expected)

    def test_apply_changes(self):
        test_cases = [
            {
                'name': 'Replace block',
                'original': """In the beginning

# @block1
original content

# @block2
keep this content

# @run
if __name__ == "__main__":
    main()""",
                'changes': """# @block1
new content""",
                'expected': """In the beginning

# @block1
new content

# @block2
keep this content

# @run
if __name__ == "__main__":
    main()"""
            },
            {
                'name': 'Add new block',
                'original': """In the beginning

# @block1
original content

# @run
if __name__ == "__main__":
    main()""",
                'changes': """# @new_block
new content""",
                'expected': """In the beginning

# @new_block
new content

# @block1
original content

# @run
if __name__ == "__main__":
    main()"""
            },
                        {
                'name': 'Order blocks',
                'original': """In the beginning

# @block1
content1

# @block2
content2

# @run
if __name__ == "__main__":
    main()""",
                'changes': """# @ORDER
block2
block1
run""",
                'expected': """In the beginning

# @block2
content2

# @block1
content1

# @run
if __name__ == "__main__":
    main()"""
            },
            {
                'name': 'Multiple new blocks',
                'original': """In the beginning

# @block1
content1

# @run
if __name__ == "__main__":
    main()""",
                'changes': """# @new_block1
new content1

# @new_block2
new content2

# @block1
updated content1""",
                'expected': """In the beginning

# @new_block1
new content1

# @new_block2
new content2

# @block1
updated content1

# @run
if __name__ == "__main__":
    main()"""
            }
        ]

        for case in test_cases:
            with self.subTest(case['name']):
                result = apply_changes(case['original'], case['changes'])
                self.assertEqual(result, case['expected'])

# @run
if __name__ == '__main__':
    unittest.main()
