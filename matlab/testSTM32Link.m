function report = testSTM32Link(port)
%TESTSTM32LINK Test a flashed board, with the GUI and other terminals closed.
%   report = testSTM32Link("COM5")
%   Requires ModularICTestApp.m on the MATLAB path (decoder only; no UI opens).
s = serialport(port, 115200, 'Timeout', 0.5);
cleanup = onCleanup(@() closeLink(s)); %#ok<NASGU>
configureTerminator(s, 'LF');
flush(s);
sourceSeen = false;

writeline(s, 'STOP,1');
waitReply('ACK', 1);
writeline(s, 'CFG,2,9,3.3,1.25,0.5,100000000,50,0,0');
waitReply('ERR', 2);
writeline(s, 'CFG,3,1.8,3.3,1.25,0.5,100000000,50,0,0');
waitReply('ACK', 3);
writeline(s, 'START,4');
waitReply('ACK', 4);

samples = zeros(10, 5);
count = 0;
deadline = tic;
while count < 10 && toc(deadline) < 3
    message = readMessage();
    if strcmp(message.Kind, 'DATA')
        count = count + 1;
        samples(count, :) = message.Values;
    end
end
assert(count == 10, 'Capstone:NoData', 'Did not receive 10 valid samples.');
assert(all(diff(samples(:, 1)) > 0), 'Capstone:Time', 'Timestamps are not increasing.');
assert(all(all(samples(:, 2:4) == 0)), 'Capstone:DisabledRails', ...
    'Expected zero simulated rail voltage/current with both rails disabled.');
assert(sourceSeen, 'Capstone:Source', 'Board did not identify its SIMULATED source.');

writeline(s, 'STOP,5');
waitReply('ACK', 5);
pause(0.2);
while s.NumBytesAvailable > 0
    message = readMessage();
    assert(~strcmp(message.Kind, 'DATA'), 'Capstone:Stop', 'DATA arrived after STOP ACK.');
end
report = array2table(samples, 'VariableNames', ...
    {'Timestamp_ms', 'Rail1_V', 'Rail2_V', 'DUTCurrent_mA', 'AnalogInput_V'});
disp('PASS: STOP, rejected CFG, valid CFG, START, source disclosure, timestamps, DATA, STOP ordering.');

    function message = readMessage()
        message = ModularICTestApp.decodeLine(readline(s));
        if strcmp(message.Kind, 'STATUS') && strcmp(message.Text, 'SOURCE,SIMULATED')
            sourceSeen = true;
        end
    end

    function waitReply(expected, id)
        start = tic;
        while toc(start) < 3
            message = readMessage();
            if any(strcmp(message.Kind, {'ACK', 'ERR'})) && message.ID == id
                assert(strcmp(message.Kind, expected), 'Capstone:Reply', ...
                    'Unexpected reply to command %d: %s %s', id, message.Kind, message.Text);
                return;
            end
        end
        error('Capstone:Timeout', 'No matching %s for command %d.', expected, id);
    end
end

function closeLink(s)
try
    writeline(s, 'STOP,999999');
catch
    % Still release the serial port after an unplug or failed test.
end
delete(s);
end
