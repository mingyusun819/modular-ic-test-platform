classdef ModularICTestApp < handle
    %MODULARICTESTAPP Desktop GUI for the modular IC test platform.
    %   app = ModularICTestApp opens the GUI in offline demo mode.
    %   Requires MATLAB R2021a or later. No add-on toolboxes are used.
    %   Serial mode requires firmware implementing docs/serial-protocol.md.

    properties (SetAccess = private)
        Figure
    end

    properties (Access = private)
        UI = struct()
        Serial = []
        UpdateTimer = []
        Random
        Connected = false
        Running = false
        Closing = false
        Configured = false
        Dirty = true
        Demo = true
        Config = struct()
        Pending = []
        NextID = 1
        RunClock = []
        LastReceive = []
        FirstRawTime = NaN
        LastRawTime = -Inf
        SampleCount = 0
        Data = zeros(50000, 5)
        CaptureMode = 'Demo (simulated)'
        DeviceSource = 'unverified source'
        BadLines = 0
        LogLines = {}
    end

    methods
        function app = ModularICTestApp(visibility)
            if nargin < 1
                visibility = 'on';
            end
            app.Random = RandStream('mt19937ar', 'Seed', 819);
            try
                app.buildUI();
                app.UpdateTimer = timer('ExecutionMode', 'fixedSpacing', ...
                    'Period', 0.1, 'Tag', 'ModularICTestAppTimer', ...
                    'TimerFcn', @(~, ~) app.tick(), ...
                    'ErrorFcn', @(~, ~) app.timerFailed());
                app.refreshPorts();
                app.updateControls();
                app.log('Ready. Select Demo, connect, apply settings, then start a capture.');
                app.Figure.Visible = visibility;
            catch err
                delete(app);
                rethrow(err);
            end
        end

        function result = getData(app)
            % Return a copy of the retained capture, including its source.
            result = array2table(app.Data(1:app.SampleCount, :), ...
                'VariableNames', {'Time_s', 'Rail1_V', 'Rail2_V', ...
                'DUTCurrent_mA', 'AnalogInput_V'});
            result.Source = repmat(string(app.CaptureMode), height(result), 1);
        end

        function delete(app)
            if app.Closing
                return;
            end
            app.Closing = true;
            app.releaseTransport();
            if ~isempty(app.UpdateTimer) && isvalid(app.UpdateTimer)
                stop(app.UpdateTimer);
                delete(app.UpdateTimer);
            end
            if ~isempty(app.Figure) && isvalid(app.Figure)
                app.Figure.CloseRequestFcn = [];
                app.Figure.DeleteFcn = [];
                delete(app.Figure);
            end
        end
    end

    methods (Access = private)
        function buildUI(app)
            bg = [0.95 0.96 0.98];
            ink = [0.10 0.16 0.24];
            blue = [0.08 0.39 0.78];
            teal = [0.00 0.57 0.48];
            screen = get(groot, 'ScreenSize');
            width = max(700, min(1320, screen(3) - 80));
            height = max(500, min(860, screen(4) - 100));
            app.Figure = uifigure('Name', 'Modular IC Test Platform', ...
                'Position', [screen(1) + 40 screen(2) + 40 width height], ...
                'Color', bg, 'Visible', 'off', ...
                'CloseRequestFcn', @(~, ~) delete(app), ...
                'DeleteFcn', @(~, ~) delete(app));
            root = uigridlayout(app.Figure, [3 2], 'RowHeight', {68, '1x', 126}, ...
                'ColumnWidth', {330, '1x'}, 'Padding', [16 16 16 16], ...
                'RowSpacing', 12, 'ColumnSpacing', 12, 'BackgroundColor', bg);

            header = uigridlayout(root, [2 2], 'RowHeight', {30, 20}, ...
                'ColumnWidth', {'1x', 230}, 'BackgroundColor', ink, ...
                'Padding', [16 8 16 8], 'RowSpacing', 2);
            app.place(header, 1, [1 2]);
            titleLabel = uilabel(header, 'Text', 'MODULAR IC TEST PLATFORM', ...
                'FontSize', 22, 'FontWeight', 'bold', 'FontColor', [1 1 1]);
            app.place(titleLabel, 1, 1);
            app.UI.Source = uilabel(header, 'Text', 'Demo mode | simulated measurements', ...
                'FontColor', [0.72 0.81 0.90], 'FontSize', 12);
            app.place(app.UI.Source, 2, 1);
            app.UI.Status = uilabel(header, 'Text', 'DISCONNECTED', ...
                'FontWeight', 'bold', 'FontColor', [1 0.78 0.38], ...
                'HorizontalAlignment', 'right');
            app.place(app.UI.Status, [1 2], 2);

            sidebar = uigridlayout(root, [3 1], ...
                'RowHeight', {'1x', 82, 40}, 'Padding', [0 0 0 0], ...
                'BackgroundColor', bg, 'RowSpacing', 10);
            app.place(sidebar, 2, 1);
            settingsGrid = uigridlayout(sidebar, [3 1], 'Scrollable', 'on', ...
                'RowHeight', {162, 284, 142}, 'Padding', [0 0 0 0], ...
                'BackgroundColor', bg, 'RowSpacing', 10);

            panel = uipanel(settingsGrid, 'Title', 'Connection', 'BackgroundColor', [1 1 1]);
            g = uigridlayout(panel, [4 3], 'RowHeight', {26, 26, 26, 28}, ...
                'ColumnWidth', {65, '1x', 66}, 'Padding', [10 8 10 8], 'RowSpacing', 5);
            app.place(uilabel(g, 'Text', 'Mode'), 1, 1);
            app.UI.Mode = uidropdown(g, 'Items', {'Demo (offline)', 'STM32 serial'}, ...
                'ValueChangedFcn', @(~, ~) app.modeChanged());
            app.place(app.UI.Mode, 1, [2 3]);
            app.place(uilabel(g, 'Text', 'Port'), 2, 1);
            app.UI.Port = uidropdown(g, 'Items', {'No ports found'});
            app.place(app.UI.Port, 2, 2);
            app.UI.Refresh = uibutton(g, 'Text', 'Refresh', ...
                'ButtonPushedFcn', @(~, ~) app.refreshPorts());
            app.place(app.UI.Refresh, 2, 3);
            app.place(uilabel(g, 'Text', 'Baud'), 3, 1);
            app.UI.Baud = uidropdown(g, 'Items', {'115200', '230400', '460800', '921600'});
            app.place(app.UI.Baud, 3, [2 3]);
            app.UI.Connect = uibutton(g, 'Text', 'Connect', 'Tag', 'ConnectButton', ...
                'ButtonPushedFcn', @(~, ~) app.toggleConnection());
            app.place(app.UI.Connect, 4, [1 3]);

            panel = uipanel(settingsGrid, 'Title', 'Power & stimulus', 'BackgroundColor', [1 1 1]);
            g = uigridlayout(panel, [8 3], 'ColumnWidth', {'1x', 86, 48}, ...
                'RowHeight', {27, 27, 27, 27, 27, 30, 22, 22}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 5);
            app.UI.Rail1 = app.number(g, 1, 'Rail 1 (V)', 1.8, [0.8 3.3], '%.3f');
            app.UI.Rail2 = app.number(g, 2, 'Rail 2 (V)', 3.3, [0.8 3.3], '%.3f');
            app.UI.Enable1 = uicheckbox(g, 'Text', 'On', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.markDirty());
            app.place(app.UI.Enable1, 1, 3);
            app.UI.Enable2 = uicheckbox(g, 'Text', 'On', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.markDirty());
            app.place(app.UI.Enable2, 2, 3);
            app.UI.VRef = app.number(g, 3, 'Voltage ref. (V)', 1.25, [0.2 3], '%.3f');
            app.UI.IRef = app.number(g, 4, 'Current ref. (uA)', 500, [100 1000], '%.0f');
            app.UI.Clock = app.number(g, 5, 'Clock (MHz)', 100, [1 200], '%.3f');
            app.UI.Apply = uibutton(g, 'Text', 'Apply settings', 'Tag', 'ApplyButton', ...
                'BackgroundColor', blue, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~, ~) app.applySettings());
            app.place(app.UI.Apply, 6, [1 3]);
            app.UI.Applied = uilabel(g, 'Text', 'Settings not applied', 'FontSize', 11);
            app.place(app.UI.Applied, 7, [1 3]);
            app.place(uilabel(g, 'Text', 'Stop capture does not switch off supplies.', ...
                'FontSize', 10), 8, [1 3]);

            panel = uipanel(settingsGrid, 'Title', 'Capture', 'BackgroundColor', [1 1 1]);
            g = uigridlayout(panel, [3 2], 'ColumnWidth', {'1x', 90}, ...
                'RowHeight', {28, 28, 28}, 'Padding', [10 8 10 8], 'RowSpacing', 5);
            app.UI.Rate = app.number(g, 1, 'Monitor rate (Hz)', 50, [10 200], '%.0f');
            app.UI.Rate.RoundFractionalValues = 'on';
            app.UI.Duration = app.number(g, 2, 'Duration (s)', 30, [1 3600], '%.1f');
            app.UI.Window = app.number(g, 3, 'Plot window (s)', 10, [1 120], '%.1f');
            app.UI.Window.ValueChangedFcn = @(~, ~) app.render();

            g = uigridlayout(sidebar, [2 2], 'RowHeight', {34, 34}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 6, 'ColumnSpacing', 8);
            app.UI.Start = uibutton(g, 'Text', 'Start new capture', 'Tag', 'StartButton', ...
                'BackgroundColor', teal, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~, ~) app.startCapture());
            app.UI.Stop = uibutton(g, 'Text', 'Stop capture', 'Tag', 'StopButton', ...
                'ButtonPushedFcn', @(~, ~) app.stopCapture());
            app.UI.Export = uibutton(g, 'Text', 'Export CSV', ...
                'ButtonPushedFcn', @(~, ~) app.exportCSV());
            app.UI.Clear = uibutton(g, 'Text', 'Clear plots', 'Tag', 'ClearButton', ...
                'ButtonPushedFcn', @(~, ~) app.clearCapture());
            note = uilabel(sidebar, 'Text', ...
                'A new capture replaces the previous data. Export first.', ...
                'WordWrap', 'on', 'FontColor', [0.36 0.42 0.50], 'FontSize', 11);
            app.place(note, 3, 1);

            charts = uigridlayout(root, [3 2], 'RowHeight', {76, '1x', '1x'}, ...
                'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'BackgroundColor', bg, 'ColumnSpacing', 12, 'RowSpacing', 12);
            app.place(charts, 2, 2);
            metrics = uigridlayout(charts, [1 4], 'Padding', [0 0 0 0], ...
                'ColumnWidth', {'1x', '1x', '1x', '1x'}, 'BackgroundColor', bg);
            app.place(metrics, 1, [1 2]);
            names = {'RAIL 1', 'RAIL 2', 'DUT CURRENT', 'ANALOG INPUT'};
            app.UI.Metrics = gobjects(1, 4);
            for k = 1:4
                p = uipanel(metrics, 'BackgroundColor', [1 1 1]);
                card = uigridlayout(p, [2 1], 'RowHeight', {18, '1x'}, ...
                    'Padding', [10 6 10 6], 'RowSpacing', 2);
                uilabel(card, 'Text', names{k}, 'FontSize', 10, ...
                    'FontColor', [0.39 0.45 0.53]);
                app.UI.Metrics(k) = uilabel(card, 'Text', '--', 'FontSize', 23, ...
                    'FontWeight', 'bold', 'FontColor', ink);
            end
            app.UI.Axes = gobjects(1, 4);
            chartNames = {'Supply rail voltage', 'DUT current', ...
                'Analog input waveform', 'Analog input spectrum (AC)'};
            yNames = {'Voltage (V)', 'Current (mA)', 'Voltage (V)', 'Amplitude (V peak)'};
            for k = 1:4
                p = uipanel(charts, 'BackgroundColor', [1 1 1]);
                app.place(p, 2 + floor((k - 1) / 2), 1 + mod(k - 1, 2));
                grid = uigridlayout(p, [1 1], 'Padding', [6 6 6 6]);
                ax = uiaxes(grid, 'FontSize', 11);
                app.UI.Axes(k) = ax;
            end
            app.UI.RailLines = plot(app.UI.Axes(1), NaN, NaN, NaN, NaN, 'LineWidth', 1.5);
            app.UI.RailLines(1).Color = blue;
            app.UI.RailLines(2).Color = teal;
            legend(app.UI.Axes(1), {'Rail 1', 'Rail 2'}, 'Location', 'best');
            app.UI.CurrentLine = plot(app.UI.Axes(2), NaN, NaN, 'Color', [0.83 0.42 0.10], 'LineWidth', 1.4);
            app.UI.SignalLine = plot(app.UI.Axes(3), NaN, NaN, 'Color', blue, 'LineWidth', 1.2);
            app.UI.SpectrumLine = plot(app.UI.Axes(4), NaN, NaN, 'Color', [0.48 0.29 0.77], 'LineWidth', 1.4);
            % Set labels after plot(), which resets axes with NextPlot=replace.
            for k = 1:4
                ax = app.UI.Axes(k);
                title(ax, chartNames{k});
                xlabel(ax, 'Time (s)');
                ylabel(ax, yNames{k});
                ax.XGrid = 'on';
                ax.YGrid = 'on';
                ax.Box = 'off';
            end
            xlabel(app.UI.Axes(4), 'Frequency (Hz)');

            footer = uigridlayout(root, [2 1], 'RowHeight', {22, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 4, 'BackgroundColor', bg);
            app.place(footer, 3, [1 2]);
            app.UI.Count = uilabel(footer, 'Text', '0 samples | No capture', 'FontColor', ink);
            app.UI.Log = uitextarea(footer, 'Editable', 'off', 'FontSize', 11);
        end

        function field = number(app, parent, row, label, value, limits, format)
            app.place(uilabel(parent, 'Text', label, 'FontSize', 12), row, 1);
            field = uieditfield(parent, 'numeric', 'Value', value, 'Limits', limits, ...
                'ValueDisplayFormat', format, 'ValueChangedFcn', @(~, ~) app.markDirty());
            app.place(field, row, 2);
        end

        function modeChanged(app)
            app.Demo = strcmp(app.UI.Mode.Value, 'Demo (offline)');
            app.UI.Enable1.Value = app.Demo;
            app.UI.Enable2.Value = app.Demo;
            app.Configured = false;
            app.markDirty();
            if app.Demo
                app.UI.Source.Text = 'Demo mode | simulated measurements';
            else
                app.UI.Source.Text = 'STM32 serial | firmware protocol required';
            end
        end

        function markDirty(app)
            app.Dirty = true;
            app.UI.Applied.Text = 'Changes not applied';
            app.updateControls();
        end

        function refreshPorts(app)
            previous = app.UI.Port.Value;
            try
                ports = cellstr(serialportlist('available'));
            catch
                ports = {};
            end
            if isempty(ports)
                ports = {'No ports found'};
            end
            app.UI.Port.Items = ports;
            if any(strcmp(ports, previous))
                app.UI.Port.Value = previous;
            else
                app.UI.Port.Value = ports{1};
            end
        end

        function toggleConnection(app)
            if app.Connected
                app.disconnect();
                return;
            end
            try
                if ~app.Demo
                    if strcmp(app.UI.Port.Value, 'No ports found')
                        error('Capstone:NoPort', 'Connect the board and refresh the serial-port list.');
                    end
                    app.Serial = serialport(app.UI.Port.Value, str2double(app.UI.Baud.Value), 'Timeout', 0.5);
                    configureTerminator(app.Serial, 'LF');
                    flush(app.Serial);
                end
                app.Connected = true;
                app.Configured = false;
                app.Dirty = true;
                app.BadLines = 0;
                if ~app.Demo
                    app.DeviceSource = 'unverified source';
                    app.UI.Source.Text = 'STM32 serial | awaiting device source';
                    configureCallback(app.Serial, 'terminator', @(src, ~) app.receive(src));
                end
                start(app.UpdateTimer);
                if ~app.Demo
                    % Recover a board left streaming by a prior host session.
                    app.sendRequest('STOP', '', struct());
                end
                app.log('Connected. Apply settings before starting a capture.');
                app.UI.Applied.Text = 'Settings not applied';
                app.updateControls();
            catch err
                app.disconnect();
                app.showError(err.message);
            end
        end

        function releaseTransport(app)
            if ~isempty(app.Serial)
                % Best-effort capture stop; this never claims outputs are off.
                try
                    if app.Running || ~isempty(app.Pending)
                        writeline(app.Serial, sprintf('STOP,%d', app.NextID));
                        app.NextID = app.NextID + 1;
                    end
                    configureCallback(app.Serial, 'off');
                catch
                    % The device may already be unplugged.
                end
                try
                    delete(app.Serial);
                catch
                    % Cleanup must still remove the app's timer and window.
                end
                app.Serial = [];
            end
        end

        function disconnect(app)
            hadHardwareRun = ~app.Demo && (app.Running || ~isempty(app.Pending));
            app.releaseTransport();
            if ~isempty(app.UpdateTimer) && isvalid(app.UpdateTimer)
                stop(app.UpdateTimer);
            end
            app.Connected = false;
            app.Running = false;
            app.Configured = false;
            app.Pending = [];
            app.UI.Applied.Text = 'Settings not applied';
            app.log('Disconnected. Captured data remains available for export.');
            if hadHardwareRun
                app.log('Hardware stop was not confirmed. Check the DUT and supply state.');
            end
            app.updateControls();
        end

        function settings = readSettings(app)
            settings = struct('Rail1', app.UI.Rail1.Value, 'Rail2', app.UI.Rail2.Value, ...
                'VRef', app.UI.VRef.Value, 'IRef_mA', app.UI.IRef.Value / 1000, ...
                'Clock_Hz', app.UI.Clock.Value * 1e6, 'Rate', app.UI.Rate.Value, ...
                'Duration', app.UI.Duration.Value, ...
                'Enable1', app.UI.Enable1.Value, 'Enable2', app.UI.Enable2.Value);
            values = [settings.Rail1 settings.Rail2 settings.VRef settings.IRef_mA ...
                settings.Clock_Hz settings.Rate settings.Duration];
            if any(~isfinite(values))
                error('Capstone:Settings', 'All settings must be finite numbers.');
            end
        end

        function applySettings(app)
            if ~app.Connected || app.Running || ~isempty(app.Pending)
                return;
            end
            try
                settings = app.readSettings();
                if app.Demo
                    app.Config = settings;
                    app.Configured = true;
                    app.Dirty = false;
                    app.UI.Applied.Text = 'Applied to demo';
                    app.log('Demo settings applied. Clock is a setpoint only in demo mode.');
                else
                    % Keep estimated ASCII traffic below 70% of UART capacity.
                    baud = str2double(app.UI.Baud.Value);
                    if settings.Rate * 96 * 10 > 0.7 * baud
                        error('Capstone:Bandwidth', ...
                            'Monitor rate is too high for this baud rate. Lower it or choose a faster baud rate.');
                    end
                    payload = sprintf(',%.6g,%.6g,%.6g,%.6g,%.0f,%d,%d,%d', ...
                        settings.Rail1, settings.Rail2, settings.VRef, settings.IRef_mA, ...
                        settings.Clock_Hz, settings.Rate, settings.Enable1, settings.Enable2);
                    app.sendRequest('CFG', payload, settings);
                end
                app.updateControls();
            catch err
                app.showError(err.message);
            end
        end

        function sendRequest(app, kind, payload, settings)
            id = app.NextID;
            app.NextID = id + 1;
            app.Pending = struct('Kind', kind, 'ID', id, 'Clock', tic, 'Settings', settings);
            command = sprintf('%s,%d%s', kind, id, payload);
            try
                writeline(app.Serial, command);
                app.log(['TX ' command]);
                app.updateControls();
            catch err
                app.disconnect();
                rethrow(err);
            end
        end

        function startCapture(app)
            if ~app.Connected || app.Running || ~isempty(app.Pending) || ~app.Configured || app.Dirty
                return;
            end
            try
                if app.Demo
                    app.beginRun();
                else
                    app.sendRequest('START', '', struct());
                end
            catch err
                app.showError(err.message);
            end
        end

        function beginRun(app)
            app.clearCapture();
            app.CaptureMode = ['STM32 serial (' app.DeviceSource ')'];
            if app.Demo
                app.CaptureMode = 'Demo (simulated)';
            end
            app.RunClock = tic;
            app.LastReceive = tic;
            app.Running = true;
            app.log(['Capture started: ' app.CaptureMode]);
            app.updateControls();
        end

        function stopCapture(app)
            if ~app.Running || ~isempty(app.Pending)
                return;
            end
            try
                if app.Demo
                    app.finishRun();
                else
                    app.sendRequest('STOP', '', struct());
                end
            catch err
                app.showError(err.message);
            end
        end

        function finishRun(app)
            app.Running = false;
            app.log(sprintf('Capture stopped. %d samples retained.', app.SampleCount));
            app.render();
            app.updateControls();
        end

        function clearCapture(app)
            if app.Running
                return;
            end
            app.SampleCount = 0;
            app.FirstRawTime = NaN;
            app.LastRawTime = -Inf;
            lines = [app.UI.RailLines(:); app.UI.CurrentLine; ...
                app.UI.SignalLine; app.UI.SpectrumLine];
            for k = 1:numel(lines)
                set(lines(k), 'XData', NaN, 'YData', NaN);
            end
            for k = 1:4
                app.UI.Metrics(k).Text = '--';
            end
            app.UI.Count.Text = '0 samples | No capture';
            app.updateControls();
        end

        function tick(app)
            if ~isvalid(app) || app.Closing || ~app.Connected
                return;
            end
            if ~isempty(app.Pending) && toc(app.Pending.Clock) > 3
                app.disconnect();
                app.showError('Command acknowledgement timed out. Connection closed; check hardware state before reconnecting.');
                return;
            end
            if app.Running
                if app.Demo
                    elapsed = min(toc(app.RunClock), app.Config.Duration);
                    target = min(size(app.Data, 1), floor(elapsed * app.Config.Rate));
                    count = target - app.SampleCount;
                    if count > 0
                        t = (app.SampleCount:target - 1)' / app.Config.Rate;
                        noise = 0.002 * randn(app.Random, count, 4);
                        c = app.Config;
                        v1 = double(c.Enable1) * (c.Rail1 + 0.004 * sin(2*pi*0.7*t) + noise(:, 1));
                        v2 = double(c.Enable2) * (c.Rail2 + 0.005 * sin(2*pi*0.5*t) + noise(:, 2));
                        current = double(c.Enable1 || c.Enable2) * ...
                            max(0, c.IRef_mA * (1 + 0.08 * sin(2*pi*0.8*t)) + noise(:, 3));
                        signal = c.VRef + 0.12 * sin(2*pi*2*t) + ...
                            0.025 * sin(2*pi*3*t) + noise(:, 4);
                        app.Data(app.SampleCount + 1:target, :) = [t v1 v2 current signal];
                        app.SampleCount = target;
                    end
                elseif toc(app.LastReceive) > 5 && isempty(app.Pending)
                    app.log('No valid measurements for 5 seconds; requesting capture stop.');
                    app.stopCapture();
                end
                if app.SampleCount >= size(app.Data, 1) && isempty(app.Pending)
                    app.log('50,000-sample capture limit reached. Export this capture before restarting.');
                    app.stopCapture();
                elseif toc(app.RunClock) >= app.Config.Duration && isempty(app.Pending)
                    app.stopCapture();
                end
            end
            app.render();
            app.updateControls();
        end

        function receive(app, source)
            if ~isvalid(app) || app.Closing || ~app.Connected
                return;
            end
            if isempty(app.Serial) || ~isequal(source, app.Serial)
                return; % Discard a callback queued by an old connection.
            end
            try
                message = app.decodeLine(readline(source));
                switch message.Kind
                    case 'DATA'
                        if ~app.Running || app.SampleCount >= size(app.Data, 1)
                            return;
                        end
                        row = message.Values;
                        if row(1) <= app.LastRawTime
                            app.badLine('Discarded non-increasing device timestamp.');
                            return;
                        end
                        app.LastRawTime = row(1);
                        if isnan(app.FirstRawTime)
                            app.FirstRawTime = row(1);
                        end
                        row(1) = (row(1) - app.FirstRawTime) / 1000;
                        app.SampleCount = app.SampleCount + 1;
                        app.Data(app.SampleCount, :) = row;
                        app.LastReceive = tic;
                    case {'ACK', 'ERR'}
                        app.handleReply(message);
                    case 'STATUS'
                        app.handleStatus(message.Text);
                    otherwise
                        app.badLine('Discarded malformed or unknown serial message.');
                end
            catch err
                app.disconnect();
                app.showError(['Serial read failed: ' err.message]);
            end
        end

        function handleStatus(app, text)
            app.log(['RX ' text]);
            if strcmp(text, 'SOURCE,SIMULATED')
                app.DeviceSource = 'simulated';
                app.UI.Source.Text = 'STM32 serial | simulated measurements';
            elseif strcmp(text, 'SOURCE,HARDWARE')
                app.DeviceSource = 'hardware-reported';
                app.UI.Source.Text = 'STM32 serial | hardware-reported measurements';
            elseif strcmp(text, 'STOPPED,CAPTURE_LIMIT') && app.Running
                app.finishRun();
            end
        end

        function handleReply(app, message)
            if isempty(app.Pending) || message.ID ~= app.Pending.ID
                app.badLine('Ignored reply with no matching request ID.');
                return;
            end
            request = app.Pending;
            app.Pending = [];
            if strcmp(message.Kind, 'ERR')
                app.log(['Device error: ' message.Text]);
                if strcmp(request.Kind, 'STOP')
                    app.disconnect();
                elseif strcmp(request.Kind, 'CFG')
                    app.Configured = false;
                    app.UI.Applied.Text = 'Device rejected settings';
                end
                app.showError(['STM32 rejected ' request.Kind ': ' message.Text]);
            else
                app.log(sprintf('RX ACK,%d (%s)', message.ID, request.Kind));
                switch request.Kind
                    case 'CFG'
                        app.Config = request.Settings;
                        app.Configured = true;
                        app.Dirty = false;
                        app.UI.Applied.Text = 'Acknowledged by STM32';
                    case 'START'
                        app.beginRun();
                    case 'STOP'
                        app.finishRun();
                end
            end
            app.updateControls();
        end

        function badLine(app, text)
            app.BadLines = app.BadLines + 1;
            if app.BadLines <= 3 || mod(app.BadLines, 100) == 0
                app.log(sprintf('%s Rejected messages: %d.', text, app.BadLines));
            end
        end

        function render(app)
            if app.SampleCount == 0
                return;
            end
            allRows = app.Data(1:app.SampleCount, :);
            latest = allRows(end, :);
            window = app.UI.Window.Value;
            rows = allRows(allRows(:, 1) >= latest(1) - window, :);
            t = rows(:, 1);
            set(app.UI.RailLines(1), 'XData', t, 'YData', rows(:, 2));
            set(app.UI.RailLines(2), 'XData', t, 'YData', rows(:, 3));
            set(app.UI.CurrentLine, 'XData', t, 'YData', rows(:, 4));
            set(app.UI.SignalLine, 'XData', t, 'YData', rows(:, 5));
            limits = [max(0, latest(1) - window), max(window, latest(1))];
            for k = 1:3
                xlim(app.UI.Axes(k), limits);
            end
            % Bound FFT work to the last 2048 points, independently of logging.
            rows = rows(max(1, size(rows, 1) - 2047):end, :);
            [frequency, amplitude] = app.spectrum(rows(:, 1), rows(:, 5));
            if isempty(frequency)
                set(app.UI.SpectrumLine, 'XData', NaN, 'YData', NaN);
            else
                set(app.UI.SpectrumLine, 'XData', frequency, 'YData', amplitude);
                xlim(app.UI.Axes(4), [0 frequency(end)]);
            end
            app.UI.Metrics(1).Text = sprintf('%.3f V', latest(2));
            app.UI.Metrics(2).Text = sprintf('%.3f V', latest(3));
            app.UI.Metrics(3).Text = sprintf('%.3f mA', latest(4));
            app.UI.Metrics(4).Text = sprintf('%.3f V', latest(5));
            app.UI.Count.Text = sprintf('%s | %d / 50,000 samples | %.2f s | Spectrum: resampled, DC removed', ...
                app.CaptureMode, app.SampleCount, latest(1));
        end

        function updateControls(app)
            if app.Closing
                return;
            end
            busy = ~isempty(app.Pending);
            editable = ~app.Running && ~busy;
            fields = {'Rail1', 'Rail2', 'Enable1', 'Enable2', 'VRef', 'IRef', 'Clock', 'Rate', 'Duration'};
            for k = 1:numel(fields)
                app.UI.(fields{k}).Enable = app.onOff(editable);
            end
            app.UI.Mode.Enable = app.onOff(~app.Connected);
            app.UI.Port.Enable = app.onOff(~app.Connected && ~app.Demo);
            app.UI.Baud.Enable = app.onOff(~app.Connected && ~app.Demo);
            app.UI.Refresh.Enable = app.onOff(~app.Connected && ~app.Demo);
            app.UI.Apply.Enable = app.onOff(app.Connected && editable);
            app.UI.Start.Enable = app.onOff(app.Connected && editable && app.Configured && ~app.Dirty);
            app.UI.Stop.Enable = app.onOff(app.Running && ~busy);
            app.UI.Export.Enable = app.onOff(app.SampleCount > 0 && ~app.Running && ~busy);
            app.UI.Clear.Enable = app.onOff(app.SampleCount > 0 && ~app.Running && ~busy);
            app.UI.Connect.Text = 'Connect';
            state = 'DISCONNECTED';
            if app.Connected
                app.UI.Connect.Text = 'Disconnect';
                state = 'CONNECTED';
                if app.Configured && ~app.Dirty
                    state = 'READY';
                end
                if app.Running
                    state = 'CAPTURING';
                end
                if busy
                    state = ['WAITING: ' app.Pending.Kind];
                end
            end
            app.UI.Status.Text = state;
        end

        function exportCSV(app)
            if app.Running || app.SampleCount == 0
                return;
            end
            mode = 'stm32';
            if strcmp(app.CaptureMode, 'Demo (simulated)')
                mode = 'demo';
            elseif strcmp(app.CaptureMode, 'STM32 serial (simulated)')
                mode = 'stm32_simulated';
            end
            name = sprintf('ic_capture_%s_%s.csv', mode, datestr(now, 'yyyymmdd_HHMMSS'));
            [file, folder] = uiputfile('*.csv', 'Export capture', name);
            if isequal(file, 0)
                return;
            end
            try
                writetable(app.getData(), fullfile(folder, file));
                app.log(['Saved ' fullfile(folder, file)]);
            catch err
                app.showError(['CSV export failed: ' err.message]);
            end
        end

        function log(app, text)
            entry = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), text);
            app.LogLines = [app.LogLines; {entry}];
            app.LogLines = app.LogLines(max(1, numel(app.LogLines) - 99):end);
            app.UI.Log.Value = app.LogLines;
        end

        function showError(app, text)
            app.log(text);
            uialert(app.Figure, text, 'Platform message');
        end

        function timerFailed(app)
            if isvalid(app) && ~app.Closing
                app.disconnect();
                app.showError('The refresh timer stopped after an error. See the MATLAB Command Window for details.');
            end
        end
    end

    methods (Static)
        function message = decodeLine(line)
            % Strict, non-executable parsing of the draft ASCII protocol.
            message = struct('Kind', 'INVALID', 'ID', NaN, 'Values', [], 'Text', '');
            if ~(ischar(line) || (isstring(line) && isscalar(line)))
                return;
            end
            line = char(line);
            if ~isrow(line) || numel(line) > 512
                return;
            end
            parts = strsplit(strtrim(line), ',', 'CollapseDelimiters', false);
            kind = strtrim(parts{1});
            if strcmp(kind, 'DATA') && numel(parts) == 6
                values = str2double(parts(2:6));
                if ~isreal(values) || any(~isfinite(values)) || values(1) < 0
                    return;
                end
                message.Kind = 'DATA';
                message.Values = values;
            elseif (strcmp(kind, 'ACK') && numel(parts) == 2) || ...
                    (strcmp(kind, 'ERR') && numel(parts) >= 3)
                id = str2double(parts{2});
                if ~isreal(id) || ~isfinite(id) || id < 1 || id ~= fix(id)
                    return;
                end
                message.Kind = kind;
                message.ID = id;
                if strcmp(kind, 'ERR')
                    message.Text = strjoin(parts(3:end), ',');
                end
            elseif strcmp(kind, 'STATUS') && numel(parts) >= 2
                message.Kind = 'STATUS';
                message.Text = strjoin(parts(2:end), ',');
            end
        end

        function [frequency, amplitude] = spectrum(time, signal)
            % One-sided peak-amplitude spectrum, with no toolbox dependency.
            frequency = [];
            amplitude = [];
            time = time(:);
            signal = signal(:);
            n = numel(time);
            if n < 16 || numel(signal) ~= n || ~isreal(time) || ~isreal(signal) || any(~isfinite(time)) || ...
                    any(~isfinite(signal)) || any(diff(time) <= 0)
                return;
            end
            uniformTime = linspace(time(1), time(end), n)';
            y = interp1(time, signal, uniformTime, 'linear');
            y = y - mean(y);
            window = 0.5 - 0.5 * cos(2*pi*(0:n - 1)' / (n - 1));
            transform = fft(y .* window);
            last = floor(n / 2) + 1;
            amplitude = abs(transform(1:last)) / sum(window);
            if mod(n, 2) == 0
                amplitude(2:end - 1) = 2 * amplitude(2:end - 1);
            else
                amplitude(2:end) = 2 * amplitude(2:end);
            end
            rate = (n - 1) / (time(end) - time(1));
            frequency = (0:last - 1)' * rate / n;
        end
    end

    methods (Static, Access = private)
        function place(component, row, column)
            component.Layout.Row = row;
            component.Layout.Column = column;
        end

        function value = onOff(condition)
            value = 'off';
            if condition
                value = 'on';
            end
        end
    end
end
