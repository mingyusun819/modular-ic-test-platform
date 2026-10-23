function tests = testModularICTestApp
% Run from matlab/: results = runtests('tests'); assertSuccess(results)
tests = functiontests(localfunctions);
end

function testTelemetryUnitsAndScientificNotation(testCase)
message = ModularICTestApp.decodeLine('DATA,1.25e3,1.801,3.299,0.502,-2.5e-2');
verifyEqual(testCase, message.Kind, 'DATA');
verifyEqual(testCase, message.Values, [1250 1.801 3.299 0.502 -0.025], 'AbsTol', 1e-12);
end

function testMalformedTelemetryIsRejected(testCase)
lines = {'', 'DATA,1,2,3,4', 'DATA,1,2,3,4,5,6', ...
    'DATA,-1,2,3,4,5', 'DATA,1,NaN,3,4,5', 'DATA,1,2,Inf,4,5', ...
    'DATA,1,,3,4,5', 'DATA,1,2+3i,3,4,5', ...
    'DATA,1,system(''echo bad''),3,4,5', repmat('X', 1, 513)};
for k = 1:numel(lines)
    message = ModularICTestApp.decodeLine(lines{k});
    verifyEqual(testCase, message.Kind, 'INVALID', lines{k});
end
end

function testRepliesAndStatus(testCase)
message = ModularICTestApp.decodeLine(sprintf('ACK,42\r\n'));
verifyEqual(testCase, message.Kind, 'ACK');
verifyEqual(testCase, message.ID, 42);
message = ModularICTestApp.decodeLine('ERR,7,RANGE,unsupported clock');
verifyEqual(testCase, message.Kind, 'ERR');
verifyEqual(testCase, message.ID, 7);
verifyEqual(testCase, message.Text, 'RANGE,unsupported clock');
message = ModularICTestApp.decodeLine('STATUS,READY');
verifyEqual(testCase, message.Kind, 'STATUS');
verifyEqual(testCase, message.Text, 'READY');
end

function testInvalidReplyIDs(testCase)
for line = {'ACK,0', 'ACK,1.5', 'ACK,NaN', 'ACK,-2', 'ACK,1,extra', 'ERR,4'}
    message = ModularICTestApp.decodeLine(line{1});
    verifyEqual(testCase, message.Kind, 'INVALID');
end
end

function testEvenSpectrumFindsToneAndRemovesDC(testCase)
t = (0:499)' / 50;
y = 1.25 + 0.12 * sin(2*pi*2*t);
[f, amplitude] = ModularICTestApp.spectrum(t, y);
[peak, index] = max(amplitude);
verifyEqual(testCase, f(index), 2, 'AbsTol', 1e-12);
verifyEqual(testCase, peak, 0.12, 'AbsTol', 1e-3);
verifyLessThan(testCase, amplitude(1), 1e-4);
verifyEqual(testCase, f(end), 25, 'AbsTol', 1e-12);
end

function testOddSpectrumScaling(testCase)
n = 501;
t = (0:n - 1)' / 100;
tone = 20 * 100 / n;
[f, amplitude] = ModularICTestApp.spectrum(t, 0.8 + 0.2*sin(2*pi*tone*t));
[peak, index] = max(amplitude);
verifyEqual(testCase, numel(f), 251);
verifyEqual(testCase, f(index), tone, 'AbsTol', 1e-12);
verifyEqual(testCase, peak, 0.2, 'AbsTol', 1e-3);
end

function testSpectrumRejectsInsufficientOrUnorderedData(testCase)
[f, a] = ModularICTestApp.spectrum((1:8)', ones(8, 1));
verifyEmpty(testCase, f);
verifyEmpty(testCase, a);
[f, a] = ModularICTestApp.spectrum([1:15 15]', ones(16, 1));
verifyEmpty(testCase, f);
verifyEmpty(testCase, a);
end

function testDemoControlsDataAndCleanup(testCase)
% This test requires MATLAB's graphics/UI support; no STM32 is needed.
before = numel(timerfindall('Tag', 'ModularICTestAppTimer'));
app = ModularICTestApp('off');
testCase.addTeardown(@() cleanupApp(app));
objects = findall(app.Figure);
axesCount = sum(arrayfun(@(x) isa(x, 'matlab.ui.control.UIAxes'), objects));
verifyEqual(testCase, axesCount, 4);
press(testCase, app, 'ConnectButton');
startButton = findall(app.Figure, 'Tag', 'StartButton');
verifyEqual(testCase, char(startButton.Enable), 'off');
press(testCase, app, 'ApplyButton');
press(testCase, app, 'StartButton');
deadline = tic;
while height(app.getData()) < 10 && toc(deadline) < 5
    pause(0.05);
    drawnow;
end
press(testCase, app, 'StopButton');
capture = app.getData();
verifyGreaterThanOrEqual(testCase, height(capture), 10);
verifyTrue(testCase, all(diff(capture.Time_s) > 0));
verifyEqual(testCase, capture.Time_s(1), 0);
verifyTrue(testCase, all(capture.Source == "Demo (simulated)"));
verifyLessThan(testCase, abs(mean(capture.Rail1_V) - 1.8), 0.02);
press(testCase, app, 'ConnectButton'); % Disconnect preserves capture.
verifyEqual(testCase, app.getData(), capture);
press(testCase, app, 'ClearButton');
verifyEmpty(testCase, app.getData());
delete(app);
verifyEqual(testCase, numel(timerfindall('Tag', 'ModularICTestAppTimer')), before);
end

function press(testCase, app, tag)
button = findall(app.Figure, 'Tag', tag);
assertEqual(testCase, numel(button), 1);
assertEqual(testCase, char(button.Enable), 'on');
callback = button.ButtonPushedFcn;
callback(button, []);
end

function cleanupApp(app)
if isvalid(app)
    delete(app);
end
end
