#!/bin/bash

# List of provinces
provinces=("Ontario" "Alberta" "Quebec" "Manitoba" "British Columbia" "Nova Scotia" "Remote")

# Lists of cities for each province
ontario_cities=("Toronto,Ottawa,Waterloo,Oakville,Markham,Mississauga,Brampton,Hamilton,London,Kitchener,Windsor,Guelph,Cambridge,Barrie,Kingston,Thunder Bay,Sudbury")
alberta_cities=("Edmonton,Calgary,Red Deer,Lethbridge,St. Albert,Medicine Hat,Grande Prairie,Airdrie,Spruce Grove,Leduc")
quebec_cities=("Montreal,Quebec City,Laval,Gatineau,Longueuil,Sherbrooke,Saguenay,Trois-Rivières,Terrebonne,Saint-Jean-sur-Richelieu,Repentigny,Drummondville,Saint-Jérôme,Granby,Blainville,Boucherville")
manitoba_cities=("Winnipeg,Steinbach,Brandon,Thompson,Portage la Prairie,Winkler,Selkirk,Morden,Dauphin,The Pas")
bc_cities=("Vancouver,Victoria,Surrey,Burnaby,Richmond,Abbotsford,Coquitlam,Kelowna,Langley,Saanich,Delta,Kamloops,Nanaimo,Chilliwack,Prince George,Penticton,Vernon,Courtenay,Campbell River,Port Coquitlam,New Westminster,Maple Ridge,North Vancouver")
nova_scotia_cities=("Halifax,Dartmouth,Sydney,Truro,New Glasgow,Glace Bay,Kentville,Amherst,Bridgewater,Yarmouth")
remote_cities=("Remote, Canada")

# Function to get cities for a given province
get_cities() {
    case $1 in
        "Ontario") echo "${ontario_cities[@]}" ;;
        "Alberta") echo "${alberta_cities[@]}" ;;
        "Quebec") echo "${quebec_cities[@]}" ;;
        "Manitoba") echo "${manitoba_cities[@]}" ;;
        "British Columbia") echo "${bc_cities[@]}" ;;
        "Nova Scotia") echo "${nova_scotia_cities[@]}" ;;
        "Remote") echo "${remote_cities[@]}" ;;
        *) echo "" ;;
    esac
}

# Step 1: Ask the user to select a province
province_str=$(printf "%s\n" "${provinces[@]}")
selected_province=$(echo "$province_str" | fzf --height 10% --border --prompt "Select a province: ")

# Step 2: Ask the user to select a city within the selected province
if [ -n "$selected_province" ]; then
    cities=$(get_cities "$selected_province")
    selected_city=$(echo "$cities" | tr ',' '\n' | fzf --height 20% --border --prompt "Select a city: ")

    # Check if a city was selected
    if [ -n "$selected_city" ]; then
        # Append the province name to the selected city
        if [ "$selected_province" == "Remote" ]; then
            echo "You selected: $selected_city"
        else
            echo "You selected: $selected_city, $selected_province"
        fi
    else
        echo "No city selected."
    fi
else
    echo "No province selected."
fi
