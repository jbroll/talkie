#!/bin/env python3
#
import sys

def read_file(filename):
    with open(filename, 'r') as file:
        return file.read()

def write_file(filename, content):
    with open(filename, 'w') as file:
        file.write(content)

def parse_blocks(content):
    blocks = {}
    block_start = 0
    current_block = 'HEADER'       # Start with the special case at the beginning of the file.
    lines = content.strip().split('\n')

    for i, line in enumerate(lines):
        if line.startswith('def ') or line.startswith('# @'):
            blocks[current_block] = '\n'.join(lines[block_start:i]).strip()
            current_block = line.startswith('def ') and line.split('(')[0][4:] or line[3:].strip()
            block_start = i

    blocks[current_block] = '\n'.join(lines[block_start:]).strip()

    return blocks

def apply_changes(original_content, changes_content):
    original_blocks = parse_blocks(original_content)
    changes_blocks = parse_blocks(changes_content)
    order_block = changes_blocks.pop('ORDER', None)

    changes_blocks.pop('HEADER')

    if order_block is None:
        # If there is no explicit order, identify new blocks so we can 
        # move them to the beginning
        #
        new_block_keys = []
        for change_key in changes_blocks.keys():
            if change_key not in original_blocks:
                new_block_keys.append(change_key)

        old_block_keys = list(original_blocks.keys())

        block_order = new_block_keys + old_block_keys
        block_order.remove('HEADER')
    else:
        block_order = order_block.strip().split('\n')[1:]

    block_order.insert(0, 'HEADER')
 
    original_blocks.update(changes_blocks)

    return '\n\n'.join(original_blocks[block] for block in block_order)

def main():
    if len(sys.argv) < 2:
        print("Usage: python update_script.py <original_file> [changes_file]")
        sys.exit(1)

    original_file = sys.argv[1]
    original_content = read_file(original_file)

    if len(sys.argv) == 3:
        changes_file = sys.argv[2]
        changes_content = read_file(changes_file)
    else:
        changes_content = sys.stdin.read()

    updated_content = apply_changes(original_content, changes_content)
    write_file(original_file, updated_content)

    print(f"Updated {original_file} with changes")

# @run
if __name__ == "__main__":
    main()
