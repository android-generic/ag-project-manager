#!/bin/bash

# SPDX-License-Identifier: GPL-2.0
#
# Android-Generic Project Manager
# Copyright (C) 2021-2023 Android-Generic Team
#
# ag-project-manager.sh 

PWD=$(pwd)
TEMP_PATH=$(mktemp -d)
SCRIPT_PATH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
echo "SCRIPT_PATH: $SCRIPT_PATH"
export PATH="$SCRIPT_PATH/core-menu/includes/:$PATH"
source $SCRIPT_PATH/core-menu/includes/easybashgui
source $SCRIPT_PATH/core-menu/includes/common.sh
export supertitle="Android Generic Project Manager"
export supericon="$SCRIPT_PATH/assets/ag-logo.png"

# Create config folder in ~/.config
mkdir -p ~/.config/ag

# Check if the config folder contains a project.cfg file that contains the location of the users projects folder
# If not, ask the location of the projects folder on the local machine and save the variable to the config file
if [ ! -f ~/.config/ag/project.cfg ]; then
    message "Please enter the location of your projects folder: "
    dselect 
    projects_path=$(0<"${dir_tmp}/${file_tmp}")
    echo "projects_path = $projects_path"
    echo "projects_path=$projects_path" >>~/.config/ag/project.cfg
else
    # If the config folder contains a project.cfg file, read the value after = from the config file
    projects_path=$(cat ~/.config/ag/project.cfg | grep projects_path | sed 's/projects_path=//g')
    echo "projects_path = $projects_path"
fi

# functions

function setupVirtenv() {
    TARGET_PROJECT_PATH=$1
    REQUIREMENTS="gcc glibc ninja-build meson"
    echo "TARGET_PROJECT_PATH: $TARGET_PROJECT_PATH"
    cd $TARGET_PROJECT_PATH
    # Check if python3 virtual environment is installed
    if [ ! -d venv ]; then
        python3 -m venv venv
        source venv/bin/activate
        pip install $REQUIREMENTS
    fi
    cd $PWD
}

function checkProjectStatus() {
    TARGET_PROJECT_PATH=$1
    cd $TARGET_PROJECT_PATH
    # Get the list of all repos
    repos=$(find $TARGET_PROJECT_PATH -type d -name ".git")

    # Create a variable to store repos that need to be pushed
    repos_to_push=""

    # Get the current projects manifest file and save it to a temp folder
    manifest=$(repo manifest -o $TEMP_PATH/manifest.xml)

    # Also get a revisional manifest for top commit ID
    revisional_manifest=$(repo manifest -o $TEMP_PATH/revisional_manifest.xml -r)

    # For each repo
    for repo in $repos; do

        # Change directory to the repo
        cd $repo

        # Get the current remote and branch
        current_remote=$(git remote show -n 1)
        current_branch=$(git branch | sed -n '1p')

        # get the path of $repo relative to $TARGET_PROJECT_PATH
        repo_path=$(echo $repo | sed 's/'$TARGET_PROJECT_PATH'/''/g')
        echo "repo_path: $repo_path"
        
        # check the $TEMP_PATH/manifest.xml for the line containing $repo_path
        # and if it does not exist, add it to $repos_to_push
        if ! grep -q "$repo_path" $TEMP_PATH/manifest.xml; then
            repos_to_push="$repos_to_push $repo"
            # Get current revision using git branch --show-current
            revision=$(git branch --show-current)
            echo "revision: $revision"
        else
            echo "repo_path already exists in $TEMP_PATH/manifest.xml"
            # grab the revision=* value from the line that $repo_path is on
            revision=$(grep "$repo_path" $TEMP_PATH/manifest.xml | sed 's/revision=//g')
            echo "revision: $revision"
            # check for uncommitted changes
            if [ -n "$(git status --porcelain)" ]; then
                echo "repo has uncommitted changes"
                repos_to_push="$repos_to_push $repo"
            fi

            # Check if the top commit ID matches up with the revisional_manifest for this repo
            rv_revision=$(grep "$repo_path" $TEMP_PATH/revisional_manifest.xml | sed 's/revision=//g')
            echo "rv_revision: $rv_revision"
            # use git log to get the top commit ID
            top_commit_id=$(git log -n 1 --pretty=format:%H)
            echo "top_commit_id: $top_commit_id"
            if [ "$top_commit_id" != "$rv_revision" ]; then
                repos_to_push="$repos_to_push $repo"
            fi
        fi
        
        # Get the current date and time
        current_date=$(date +"%Y%m%d%H%M%S")
        # Save $repos_to_push to a file and show the user using alert_dialog
        echo "$repos_to_push" >$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt

        # convert $repos_to_push to an array
        repos_array=($repos_to_push)

        alert_message "Repos that need to be pushed \n{$repos_to_push[@]}"

        cd $PWD

    done

    # If there are any repos that need to be pushed, display them and ask the user if they would like to push them
    if [[ $(cat repos_to_push.txt | wc -l) -gt 0 ]]; then
        echo "The following repos need to be pushed:"
        cat repos_to_push.txt

        # Ask the user if they would like to push the repos
        read -p "Would you like to push the repos? (y/n) " push_repos

        # If the user says yes, push the repos
        if [[ $push_repos == "y" ]]; then
            for repo in $(cat repos_to_push.txt); do
            cd $repo
            git push $current_remote $current_branch
            done
        fi
    fi

    # If the user wants to generate a manifest, generate it
    if [[ $push_repos == "y" ]]; then
        read -p "Would you like to generate a manifest now? (y/n) " generate_manifest

        # If the user says yes, generate the manifest
        if [[ $generate_manifest == "y" ]]; then
            repo manifest -o manifest.xml -r
        fi
    fi

}

function cloneAndroidGeneric() {

    TARGET_AG_PROJECT_PATH=$1

    if [[ ! -d $TARGET_AG_PROJECT_PATH/vendor/ag ]]; then
        # Ask the user if they would like to clone Android-Generic Project into their projects folder
        input 1 "Would you like to clone Android-Generic Project into your projects folder? (y/n)" "n"
        clone_answer=$(0<"${dir_tmp}/${file_tmp}")

        if [[ "$clone_answer" == "y" ]]; then
            # cd into the project folder
            cd $TARGET_AG_PROJECT_PATH
            echo "Current directory: $TARGET_AG_PROJECT_PATH"
            # clone in ag to vendor/ag
            git clone https://github.com/android-generic/vendor_ag vendor/ag
            cd $PWD
        else
            echo "Nothing to do. I guess we will have to part ways for now"
            exit 0
        fi
    else
        echo "Android-Generic Project already exists in your projects folder"
    fi


}

function deleteProject() {
    TARGET_AG_PROJECT_PATH=$1
    input 1 "Would you like to delete $TARGET_AG_PROJECT_PATH? (DELETE/n)" "n"
    DELETE_PROJECT_ANSWER=$(0<"${dir_tmp}/${file_tmp}")
    if [[ $DELETE_PROJECT_ANSWER == "DELETE" ]]; then
        rm -rf $TARGET_AG_PROJECT_PATH
    fi

}

function updateProject() {
    TARGET_AG_PROJECT_PATH=$1
    cd $TARGET_AG_PROJECT_PATH
    input 1 "Do you want to Force updates of $TARGET_AG_PROJECT_PATH? \n(WARNING: This will force updates and any unpushed changes will be lost). (y/n)" "n"
    REPO_SYNC_ANSWER=$(0<"${dir_tmp}/${file_tmp}")
    if [[ $REPO_SYNC_ANSWER == "y" ]]; then
        repo sync --force-sync
    else
        repo sync
    fi
}

# main

# Find all subfolders in the projects folder
subfolders_list=$(find $projects_path -maxdepth 1 -mindepth 1 -type d)
echo "subfolders_list = $subfolders_list"

# Save the list of subfolders to a new variable in the "projects.list" file.
echo "$subfolders_list" >~/.config/ag/projects.list

# Build a list of menu items
main_menu_items=("Initialize Supported Project" "Create New" "Setup Virtual Environment" "Check Project Status" "Add AG To Project" "Update Project" "Delete Project" "Exit")

# present the list as a menu, with a Create New option added.
menu "$subfolders_list" "${main_menu_items[@]}"
projects_answer=$(0<"${dir_tmp}/${file_tmp}")

if [[ "$projects_answer" == "Initialize Supported Project" ]]; then
    # Check $SCRIPT_PATH/projects/api-* to see what api's are supported
    # Here is a table of the Android versions and their corresponding API levels:

    # echo api versions to text function using EOF
    echo "We need to start off by selecting an Android version using the API level
    Android Version | API Level
    ---             |---
    Android 13      | 33
    Android 12.1    | 32
    Android 12      | 31
    Android 11      | 30
    Android 10      | 29
    Android 9       | 28

    Select OK to continue
    " | text
    api_levels=$(find $SCRIPT_PATH/projects/ -maxdepth 1 -mindepth 1 -type d | cut -d '-' -f 4 | sort | uniq)
    echo "api_levels = $api_levels"
    menu "$api_levels"
    api_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$api_answer" == 0 ]]; then
        echo "$api_answer is not a valid API level"
        exit 1
    fi

    # find all *.prj files in the $SCRIPT_PATH/projects/$api_answer/ folder and make a list of those projects
    eligible_project_files=$(find $SCRIPT_PATH/projects/api-$api_answer -maxdepth 1 -mindepth 1 -type f -name "*.prj")
    echo "eligible_project_files = $eligible_project_files"

    # read each of the $eligible_project_files files and create a menu entry for each project using the
    # TIITLE="*" value inside the file
    project_titles=()
    for project_file in $eligible_project_files; do
        while read -r line; do
            if [[ "$line" == *"TIITLE"* ]]; then
                echo "line = $line"
                project_pre_title=$(echo "$line" | sed 's/TIITLE=//g')
                echo "project_pre_title = $project_pre_title"
                # Add new element at the end of the array
                project_titles+=("$project_pre_title")
            fi
        done < "$project_file"
    done
    echo """project_titles = "${project_titles[@]}""""
    info "Please choose from the following supported projects: "
    menu ${project_titles[@]}
    project_title_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_title_answer" == 0 ]]; then
        echo "$project_title_answer is not a valid project title"
        exit 1
    fi
    for project_file in $eligible_project_files; do
        seleced_project="false"
        while read -r line; do
            if [[ "$line" == *"TIITLE"* ]]; then
                selected_project_pre_title=$(echo "$line" | sed 's/TIITLE=//g'|tr -d '\n\t\r ' | tr -d '"')
                echo "selected_project_pre_title: $selected_project_pre_title"
                selected_project_title_answer=$(echo "$project_title_answer"|tr -d '\n\t\r ')
                echo "selected_project_title_answer: $selected_project_title_answer"
                if [[ "$selected_project_pre_title" == "$selected_project_title_answer" ]]; then
                    seleced_project="true"
                fi
            fi
            echo "seleced_project: $seleced_project"
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"MANIFEST_URL"* ]]; then
                project_manifest_url=$(echo "$line" | sed 's/MANIFEST_URL=//g')
                echo "project_manifest_url: $project_manifest_url"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"MANIFEST_BRANCH"* ]]; then
                project_manifest_branch=$(echo "$line" | sed 's/MANIFEST_BRANCH=//g')
                echo "project_manifest_branch: $project_manifest_branch"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"REQUIRES_AG"* ]]; then
                project_requires_ag=$(echo "$line" | sed 's/REQUIRES_AG=//g')
                echo "project_requires_ag: $project_requires_ag"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"GIT_LFS"* ]]; then
                project_git_lfs=$(echo "$line" | sed 's/GIT_LFS=//g')
                echo "project_git_lfs: $project_git_lfs"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"DEPENDENCIES"* ]]; then
                project_dependencies=$(echo "$line" | sed 's/DEPENDENCIES=//g')
                echo "project_dependencies: $project_dependencies"
            fi
        done < "$project_file"

        
    done

    # check through the project_dependencies and verify that the package is installed on the host
    installed_apps=$(apt list --installed)
    needs_to_install_list=()
    for app in $project_dependencies; do

        if [[ ! $(echo $installed_apps | grep "$app") ]]; then
            echo "Package $app is not installed on the host."
            needs_to_install_list+=("$app")
        fi
    done

    if [[ ${#needs_to_install_list[@]} -gt 0 ]]; then
        info "Missing apps: ${needs_to_install_list[@]}"
        menu "Install all missing dependencies" "Cancel"
        dependencies_answer=$(0<"${dir_tmp}/${file_tmp}")
        if [[ "$dependencies_answer" == "Install all missing dependencies" ]]; then
            for app in ${needs_to_install_list[@]}; do
                sudo apt install -y $app
            done
        else
            echo "Cancelled"
            exit
        fi
    else
        echo "All dependencies are installed"
    fi

    # ask the user what they would like to name their new project folder
    input 1 "Please enter the name of your new project folder: " "eg: my_project"
    project_name=$(0<"${dir_tmp}/${file_tmp}")

    # create new project folder in the user specified location
    mkdir -p "$projects_path/$project_name"

    # cd into that folder and use the $project_manifest_url and $project_manifest_branch variables to repo init
    cd $projects_path/$project_name
    echo "moving to path: $projects_path/$project_name"

    # repo init
    project_manifest_url=$(echo "$project_manifest_url"| tr -d '"')
    echo "project_manifest_url = $project_manifest_url"
    project_manifest_branch=$(echo "$project_manifest_branch"| tr -d '"')
    echo "project_manifest_branch = $project_manifest_branch"
    if [[ "$project_git_lfs" == "true" ]]; then
        repo init -u $project_manifest_url -b $project_manifest_branch --git-lfs
    else
        repo init -u $project_manifest_url -b $project_manifest_branch
    fi
    info "repo init done, now continuing onto the initial sync"
    repo sync
    cd $PWD
    # Save the current_project_folder to the config file
    echo "current_project_folder = $project_name" >>~/.config/ag/project.cfg
elif [[ "$projects_answer" == "Create New" ]]; then
    # we need to collect all the variables needed for the .prj file
    # this is done by using the variable names in the .prj file as the keys and their values as the values

    # Ask the new project name to be created
    input 1 "Please enter the name of your new project folder (no spaces): " "project_name"
    project_name=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_name" == 0 ]]; then
        alert_message "invalid project_name"
        exit 1
    fi
    # Ask the user for the project title, for TIITLE="*"
    input 1 "Please enter the title of your new project: " "project_title"
    project_title=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_title" == 0 ]]; then
        alert_message "invalid project_title"
        exit 1
    fi

    # ask the user for their project version, for VERSION="*"
    input 1 "Please enter the version of your new project: " "0.0"
    project_version=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_version" == 0 ]]; then
        alert_message "invalid project_version"
        exit 1
    fi

    # Ask the user for a project descrtion, for DESCRIPTION="*"
    input 1 "Please enter the description of your new project: " "project_description"
    project_description=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_description" == 0 ]]; then
        alert_message "invalid project_description"
        exit 1
    fi

    # Ask the user for the project dependencies, for DEPENDENCIES="*"
    input 1 "Please enter the dependencies of your new project: " "project_dependencies"
    project_dependencies=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_dependencies" == 0 ]]; then
        alert_message "invalid project_dependencies"
        exit 1
    fi

    # Ask the user for the project manifest url, for MANIFEST_URL="*"
    input 1 "Please enter the manifest url of your new project: " "project_manifest_url"
    project_manifest_url=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_manifest_url" == 0 ]]; then
        alert_message "invalid project_manifest_url"
        exit 1
    fi

    # Ask the user for the project manifest branch, for MANIFEST_BRANCH="*"
    input 1 "Please enter the manifest branch of your new project: " "project_manifest_branch"
    project_manifest_branch=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_manifest_branch" == 0 ]]; then
        alert_message "invalid project_manifest_branch"
        exit 1
    fi

    # Ask the user if this project requires Android-Generic for building, for REQUIRES_AG="*"
    input 1 "Please enter if this project requires Android-Generic for building (true/false): " "false"
    project_requires_ag=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_requires_ag" == 0 ]]; then
        alert_message "invalid project_requires_ag"
        exit 1
    fi

    # Ask the user if this project requires GIT LFS for building, for GIT_LFS="*"
    input 1 "Please enter if this project requires GIT LFS for building (true/false): " "false"
    project_git_lfs=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_git_lfs" == 0 ]]; then
        alert_message "invalid project_git_lfs"
        exit 1
    fi

    # Ask the user the target API for this project, for our folder creation
    input 1 "Please enter the target API level for this project:" "32"
    project_target_api=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_target_api" == 0 ]]; then
        alert_message "invalid project_target_api"
        exit 1
    fi

    echo "Creating $project_name.prj"

    # Check to make sure $SCRIPT_PATH/projects/api-$project_target_api exists
    if [[ ! -d $SCRIPT_PATH/projects/api-$project_target_api ]]; then
        mkdir -p $SCRIPT_PATH/projects/api-$project_target_api
    fi

    # Create the $project_name.prj file, and save it as $SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "TITLE=$project_title" >$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "VERSION=$project_version" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "DESCRIPTION=$project_description" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "DEPENDENCIES=$project_dependencies" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "MANIFEST_URL=$project_manifest_url" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "MANIFEST_BRANCH=$project_manifest_branch" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "REQUIRES_AG=$project_requires_ag" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "GIT_LFS=$project_git_lfs" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj

    ok_message "$project_name.prj created in $SCRIPT_PATH/projects/api-$project_target_api \nYou will be given the option to commit your changes when complete."

    # Save the current_project_folder to the config file
    echo "current_project_folder = $project_name" >>~/.config/ag/project.cfg

    # create new project folder in the user specified location
    mkdir -p $projects_path/$project_name
    cd $projects_path/$project_name

    echo "Running repo init for that project now"
    if [[ "$project_git_lfs" == "true" ]]; then
        repo init -u $project_manifest_url -b $project_manifest_branch --git-lfs
    else
        repo init -u $project_manifest_url -b $project_manifest_branch
    fi

    echo "Running repo sync for that project now"
    # run repo sync command in the terminal window to show progress
    repo sync --force-sync -c
elif [[ "$projects_answer" == "Setup Virtual Environment" ]]; then
    # Select what project to setup the setupVirtenv() function for
    info "Please select which project to setup the virtual environment for"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    setupVirtenv $current_project_folder
elif [[ "$projects_answer" == "Check Project Status" ]]; then
    # Select what project to check the checkProjectStatus() function for
    info "Please select which project to check the project status for"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    checkProjectStatus $current_project_folder
elif [[ "$projects_answer" == "Delete Project" ]]; then
    # Select what project to delete the deleteProject() function for
    info "Please select which project to delete"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    deleteProject $current_project_folder
elif [[ "$projects_answer" == "Update Project" ]]; then
    # Select what project to update the updateProject() function for
    info "Please select which project to update"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    updateProject $current_project_folder
elif [[ "$projects_answer" == "Add AG To Project" ]]; then
    # Select what project to add the cloneAndroidGeneric() function for
    info "Please select which project to add AG to"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    cloneAndroidGeneric $current_project_folder
elif [[ "$projects_answer" == "Exit" ]]; then
    exit 0
elif [[ -d "$projects_answer" ]]; then
    # cd into the $projects_answer folder and set this as the current_project_folder variable
    cd $projects_answer
    current_project_folder=$projects_answer
    # Save the current_project_folder to the config file
    echo "current_project_folder = $current_project_folder" >>~/.config/ag/project.cfg
    cd $PWD
else 
    echo "not a valid selection"
    exit 0
fi

# Ask if this project requires Android-Generic
if [[ "$project_requires_ag" == "true" ]]; then
    echo "This project requires Android-Generic to be cloned thio the project folder in order to build Android-x86 (PC)" | text 
    cloneAndroidGeneric
fi

if [[ -d $current_project_folder/vendor/ag ]]; then

    # Ask if they would like to launch the AG menu option
    input 1 "Would you like to launch the Android-Generic Project Menu? (y/n)" "y"
    ag_menu_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$ag_menu_answer" == "y" ]]; then
        cd $current_project_folder
        . build/envsetup.sh
        ag-menu 
    fi
fi

# cd into the $SCRIPT_PATH
cd $SCRIPT_PATH

# Use git status to see if $SCRIPT_PATH has any changes that need to be committed
needs_updating=$(git status --porcelain)
if [[ "$needs_updating" != "" ]]; then
    # Ask the user if they would like to commit the changes
    input 1 "Would you like to commit the changes in $SCRIPT_PATH? (y/n)" "n"
    commit_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$commit_answer" == "y" ]]; then
        git add .
        git commit -m "Project $current_project_folder updated"
        info "Project $current_project_folder updated, please consider submitting your changes in a pull-request"
    else
        info "Project $current_project_folder not updated"
    fi
fi
