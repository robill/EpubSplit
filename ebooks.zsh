# Adapted from my scripts at https://github.com/NightMachinary/.shells/blob/master/scripts/zsh/auto-load/others/ebooks.zsh
epubsplit () {
    setopt local_options extended_glob re_match_pcre
    local file="$1"
    local title="${2:-Unknown title}"
    local pLn='^\s*Line Number:\s+(\d+)'
    local p1="${esP1:-toc:\s+\['\D*(\d+).*'\]}"
    local p2="${esP2:-id:\s+[cC]\D*(\d+)}"
    local i=0
    local n="${esN:-3}"
    local n1=$((n+1))
    local hasChanged=''
    local lm1=''
    local lm2=''
    local alreadyNoticed=''
    local currentSplit=0
    local split=()

    for line in "${(@f)$(epubsplit.py "$file")}"; do
        hasChanged=''

        [[ "$line" =~ "$pLn" ]] && {
            split+="$match[1]"
            alreadyNoticed=''
            continue
        }

        [[ "$line" =~ "$p1" ]] && {
            [[ "$match[1]" != "$lm1" ]] && {
                test -z "$alreadyNoticed" && hasChanged='y'
                alreadyNoticed=y
            }
            lm1="$match[1]"
        }

        [[ "$line" =~ "$p2" ]] && {
            [[ "$match[1]" != "$lm2" ]] && {
                test -z "$alreadyNoticed" && hasChanged='y'
                alreadyNoticed=y
            }
            lm2="$match[1]"
        }

        test -n "$hasChanged" && {
            i=$(( (i+1) % n1 ))
            [[ "$i" == 0 ]] && {
                i=1
                epubsplit.py --title "p${currentSplit} $title" -o "p${currentSplit} ""$file" "$file" "${(@)split[1,-2]}"
                currentSplit=$((currentSplit+1))
                split=($split[-1])
            }
        }
    done

    test -z "${split[*]}" || epubsplit.py --title "p${currentSplit} $title" -o "p${currentSplit} ""$file" "$file" "${split[@]}"
}