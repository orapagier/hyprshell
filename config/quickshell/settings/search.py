#!/usr/bin/env python3
"""Index static Settings captions without loading pages or evaluating QML."""
import ast
import json
from pathlib import Path
import re


# Source ownership mirrors SettingsWindow navigation. Captions themselves are
# extracted, so changing a heading never requires maintaining another word list.
PAGES = {
    '-1': 'SettingsBarEditor', '-2': 'SettingsAppearance', '-3': 'SettingsLocking',
    '-4': 'SettingsCleanup', '-5': 'SettingsHyprskill', '-6': 'SettingsKeybindings',
    '-7': 'SettingsDisplays', '-8': 'SettingsTheme', '-9': 'SettingsInput',
    '-10': 'SettingsPower', '-11': 'SettingsNotifications', '-12': 'SettingsSound',
    '-13': 'SettingsApplications', '-14': 'SettingsRecovery', '-15': 'SettingsNetwork',
    '-16': 'SettingsAccessibility', '-17': 'SettingsRegional', '-18': 'SettingsHelp',
    '-19': 'SettingsBehavior', '-20': 'SettingsClipboard', '-21': 'SettingsPeripherals',
    '-22': 'SettingsFirewall', '-23': 'SettingsConfigurationRecovery',
    '-25': 'SettingsBluetooth', '*': 'SettingsItemEditor',
}
TOKEN = re.compile(r'(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)|'
                   r'(?P<string>"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|'
                   r'(?P<word>[A-Za-z_]\w*)|(?P<symbol>[^\s])')
CAPTIONS = {'title', 'label', 'text', 'placeholderText'}
EXCLUDE = {'SettingsWindow', 'SettingsController', 'SettingsStore'}


def setting_caption(value, caption):
    """Keep names and control captions, not sentences of explanatory copy."""
    caption = ' '.join(caption.split())
    if value == 'text' and re.search(r'[.!?](?:\s|$)', caption):
        return ''
    return caption


def source_captions(source):
    tokens = [match for match in TOKEN.finditer(source) if match.lastgroup != 'comment']
    captions, components = [], set()
    for index, token in enumerate(tokens[:-1]):
        value = token.group()
        if token.lastgroup != 'word':
            continue
        following = tokens[index + 1].group()
        if value[0].isupper() and following == '{' and value not in EXCLUDE:
            components.add(value)
        if value not in CAPTIONS or following != ':':
            continue
        start = index + 2
        if start >= len(tokens):
            continue
        previous_end = tokens[start].start()
        for item in tokens[start:]:
            if '\n' in source[previous_end:item.start()] or item.group() in (';', '}'):
                break
            previous_end = item.end()
            if item.lastgroup != 'string':
                continue
            try:
                caption = ast.literal_eval(item.group())
            except (ValueError, SyntaxError):
                continue
            caption = setting_caption(value, caption)
            if caption and caption not in captions:
                captions.append(caption)
    return captions, components


def helper_captions(root, source):
    """Read static labels supplied by a page's helper, without importing it."""
    captions = []
    for token in TOKEN.finditer(source):
        if token.lastgroup != 'string':
            continue
        try:
            value = ast.literal_eval(token.group())
        except (SyntaxError, ValueError):
            continue
        if not re.fullmatch(r'settings/[a-z_]\w*\.py', value):
            continue
        path = root / value
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 2_000_000:
            continue
        try:
            tree = ast.parse(path.read_text())
        except SyntaxError:
            continue
        def add(node, field='label'):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                caption = setting_caption(field, node.value)
                if caption:
                    captions.append(caption)
        for node in ast.walk(tree):
            if isinstance(node, ast.Dict):
                for key, value in zip(node.keys, node.values):
                    if isinstance(key, ast.Constant) and key.value in CAPTIONS:
                        add(value, key.value)
            elif isinstance(node, ast.Call):
                for keyword in node.keywords:
                    if keyword.arg in CAPTIONS:
                        add(keyword.value, keyword.arg)
                if isinstance(node.func, ast.Name) and node.func.id == 'row' and len(node.args) > 1:
                    add(node.args[1])
    return captions


def build_index(root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parent.parent
    parsed = {}

    def collect(component, visited):
        if component in visited or component in EXCLUDE:
            return []
        visited.add(component)
        if component not in parsed:
            path = root / (component + '.qml')
            if not path.is_file() or path.is_symlink() or path.stat().st_size > 2_000_000:
                parsed[component] = ([], set())
            else:
                source = path.read_text()
                captions, children = source_captions(source)
                parsed[component] = (captions + helper_captions(root, source), children)
        captions, children = parsed[component]
        result = list(captions)
        for child in sorted(children):
            result.extend(collect(child, visited))
        return result

    return {section: list(dict.fromkeys(collect(component, set()))) for section, component in PAGES.items()}


if __name__ == '__main__':
    print(json.dumps(build_index(), ensure_ascii=False))
