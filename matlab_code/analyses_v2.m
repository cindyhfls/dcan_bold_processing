function analyses_v2(config_path)

    %% load variables from config
    conf_str = fileread(config_path);
    conf_str = strrep(conf_str, ' ', ''); % hack to get loadjson to work
    conf_json = loadjson(conf_str);

    path_wb_c = conf_json.path_wb_c;
    taskname = conf_json.taskname;
    version = conf_json.version;
    epi_TR = conf_json.epi_TR;
    summary_Dir = conf_json.summary_Dir;
    brain_radius_in_mm = conf_json.brain_radius_in_mm;
    expected_contiguous_frame_count = conf_json.expected_contiguous_frame_count;
    result_dir = conf_json.result_dir;
    path_motion_numbers = conf_json.path_motion_numbers;
    path_ciftis = conf_json.path_ciftis;
    path_timecourses = conf_json.path_timecourses;
    skip_seconds = conf_json.skip_seconds;

    %silence warnings
    warning('off', 'all')

    %% Make cat figure (Added by Oscar on Dec 10, 2015)

    % @ WARNING This is a hard coded expected file path...
    temp_files = sorter([summary_Dir filesep 'temp_grayplotdata_' ...
        taskname '*.mat'],taskname);
    cat_FD = [];
    cat_DVAR_pre_reg = [];
    cat_DVAR_post_reg = [];
    cat_DVAR_post_all = [];
    cat_Xd = [];
    cat_Rr = [];
    n_tasks = length(temp_files);

    for i=1:n_tasks
        local_file = temp_files{i};
        load(local_file);
        cat_FD = [cat_FD; nan_FD];
        cat_DVAR_pre_reg = [cat_DVAR_pre_reg nan_DVAR_pre_reg];
        cat_DVAR_post_reg = [cat_DVAR_post_reg nan_DVAR_post_reg];
        cat_DVAR_post_all = [cat_DVAR_post_all nan_DVAR_post_all];
        cat_Xd = [cat_Xd; Xd];
        cat_Rr = [cat_Rr; Rr];
        delete(local_file);
    end
    tit = [num2str(n_tasks) ' runs'];

    try
        disp('Starting fig_fMRI_QA')
        fig_fMRI_QA(['CONCA_' taskname], cat_FD, cat_Xd, cat_DVAR_pre_reg, ...
            cat_DVAR_post_reg, cat_DVAR_post_all,summary_Dir);
    catch ERROR
        disp(ERROR.message)
        disp(['there was an error creating the concatenated grayplots ' ...
            'figure.'])
        %exit
    end
    try
        disp('Starting fig_fMRI_QA_Postreg')
        fig_fMRI_QA(['CONCP_' taskname], cat_FD, cat_Rr, cat_DVAR_pre_reg, ...
            cat_DVAR_post_reg, cat_DVAR_post_all,summary_Dir);
    catch ERROR
        disp(ERROR.message)
        disp(['there was an error creating the concatenated post reg ' ...
            'grayplots figure.'])
        %exit
    end



    %%handle niftis that store TR in ms
    if (epi_TR > 20)
        epi_TR = epi_TR / 1000;
    end


    %% get the paths to motion numbers
    disp('get the paths to motion numbers')
    try
        disp(path_motion_numbers)
        FD_movement_files = sorter(path_motion_numbers,taskname);
    catch ME
        disp(ME.message)
        disp(['ERROR: Check the existence of a good Movement_Regressors.txt file.  No motion_numbers.txt file here: ' fullfile(path_motion_numbers)])
        exit
    end
    display ([num2str(length(FD_movement_files)) ...
        ' individual motion_number files were identified'])

    %% calculate content of motion folder
    subject_FD_parse_BIDS(FD_movement_files, skip_seconds, epi_TR, ...
        brain_radius_in_mm, result_dir, taskname)

    disp('starting subject_motion_numbers_TXT_parse_BIDS')
    disp(FD_movement_files)
    disp(result_dir)

    subject_motion_numbers_TXT_parse_BIDS(FD_movement_files, result_dir, taskname)

    disp('subject_motion_numbers_TXT_parse_BIDS complete')

    mat_file = subject_power_2014_FD_only_parse_BIDS(FD_movement_files, skip_seconds, ...
        epi_TR, expected_contiguous_frame_count, result_dir, taskname);
    subject_power_2014_motion_parse_opt_BIDS(FD_movement_files, ...
        skip_seconds, epi_TR, expected_contiguous_frame_count, result_dir, taskname);
    motion_summary_BIDS([result_dir filesep taskname '_motion_numbers.mat'], ...
        [result_dir filesep taskname '_power_2014_FD_only.mat'], result_dir, taskname);

    %% Make the outlier mat files
    dtseries = dir(fullfile(path_ciftis, '*.dtseries.nii'));
    if ~isempty(dtseries)
        dtseries_files = {};
        for i = 1:length(dtseries)
            dtseries_files{i} = fullfile(dtseries(i).folder,dtseries(i).name);
        end
        n_dtseries = length(dtseries_files);
        disp([num2str(n_dtseries) ...
            ' individual dtseries files were identified'])
        for i=1:n_dtseries
            try
                filename = dtseries_files{i};
                [~, name, ~] = fileparts(filename);

                subject_outliers_parse_BIDS(path_wb_c, mat_file, filename, ...
                    result_dir, taskname)

            catch exception
                disp([filename ':'])
                disp(exception)
            end
        end
    end

    %% Make the csv timecourses
    dummy = dir(fullfile(path_ciftis, '*ptseries*'));
    if ~isempty(dummy)
        ptseries_files = {};
        for i = 1:length(dummy)
            ptseries_files{i} = fullfile(dummy(i).folder,dummy(i).name);
        end
        n_ptseries = length(ptseries_files);
        disp([num2str(n_ptseries) ...
            ' individual ptseries files were identified'])
        for i=1:n_ptseries
            try
                filename = ptseries_files{i};
                [~, name, ~] = fileparts(filename);
                
                cifti_txt_path = [result_dir filesep 'temp_FNL_cifti.txt'];
                cmd = [path_wb_c ' -cifti-convert -to-text ' filename ' ' ...
                    cifti_txt_path];
                system(cmd);
                X = dlmread(cifti_txt_path);
                system(['rm -f ' cifti_txt_path]);
                
                dummy = regexp(name, [version '_'], 'split');
                dummy = regexp(dummy{2}, '.ptseries', 'split');
                csv_name = [dummy{1} '.csv'];
                csvwrite([path_timecourses filesep csv_name], X')
                disp(['Writing ' csv_name]);
            catch
                disp([name 'does not exist'])
            end
        end
    end
    
    % copy <taskname>_FD*.txt into <taskname>_all_FD.txt
    system(['rm -f ' summary_Dir filesep taskname '_all_FD.txt']);

    system(['cat ' summary_Dir filesep 'FD_' taskname '*.txt >> ' summary_Dir filesep taskname '_all_FD.txt']);

    FD = dlmread([summary_Dir filesep taskname '_all_FD.txt']);
    hist(FD, 100, 'facecolor', 'g')

    % Create FD figure
    clf('reset');
    figure1 = figure('Position', [100, 100, 1049, 895], 'Visible', 'off');

    % Create subplot
    subplot1 = subplot(2,1,1,'Parent',figure1);

    % Create title
    title('Framewise Displacement (FD) Summary');

    box(subplot1,'on');
    % Set the remaining axes properties
    set(subplot1,'CLim',[1 2]);

    % Create plot
    [Y1,X1] = hist(FD,25) ;

    stairs(X1,Y1,'Parent',subplot1,'color',[0,0,0]);

    csY1 = cumsum(Y1) ;
    yl = ylim ;
    hold all ;
    stairs(X1,csY1/csY1(end)*yl(2),'color',[0,0,1],'linewidth',3) ;
    hold off

    % Create ylabel
    ylabel('HIST & CDF');
    legend('FD counts', 'Cumulative FD')
    % Create subplot
    subplot2 = subplot(2,1,2,'Parent',figure1);
    hold(subplot2,'on');

    % Create scatter
    scatter(FD, zeros(length(FD), 1) + abs((randn(length(FD),1))), ...
        'r', '+', 'Parent', subplot2);

    % Create xlabel
    xlabel('Framewise Displacement (mm)');

    % Create ylabel
    ylabel('Points');

    %% Uncomment the following line to preserve the Y-limits of the axes
    ylim(subplot2,[-10 10]);

    saveas(figure1, [ summary_Dir filesep taskname '_FD_dist.png' ])

    exit
end
