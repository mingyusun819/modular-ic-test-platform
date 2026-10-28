% Smoke test the actual serial-to-display path without starting a capture.
addpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'matlab'));
app = ModularICTestApp('off');
cleanup = onCleanup(@() delete(app));
menus = findall(app.Figure, 'Type', 'uidropdown');
for k = 1:numel(menus)
    if any(strcmp(menus(k).Items, 'STM32 serial'))
        menus(k).Value = 'STM32 serial';
        menus(k).ValueChangedFcn(menus(k), []);
    end
end
for k = 1:numel(menus)
    if any(strcmp(menus(k).Items, 'COM3'))
        menus(k).Value = 'COM3';
    end
end
button = findall(app.Figure, 'Tag', 'ConnectButton');
button.ButtonPushedFcn(button, []);
pause(3);
labels = findall(app.Figure, 'Type', 'uilabel');
texts = string({labels.Text});
reading = texts(startsWith(texts, 'MCU VDDA:'));
disp(reading);
assert(numel(reading) == 1 && contains(reading, ' V'), 'No measured supply displayed.');
button.ButtonPushedFcn(button, []);
assert(strcmp(labels(startsWith(texts, 'MCU VDDA:')).Text, 'MCU VDDA: --'));
delete(app);
clear cleanup;
