pacman::p_load(tidyverse, lubridate, ggrepel)

# http://users.econ.umn.edu/~holmes/data/WalMart/
dat <- read_csv('https://byuistats.github.io/M335/data/Walmart_store_openings.csv') 

# https://dev.socrata.com/foundry/brigades.opendatanetwork.com/5gyf-irpw/no-redirect
locs <- read_csv('https://byuistats.github.io/M335/data/Walmart_Stores_Locations.csv') %>%
  mutate(`Contact Info` = str_replace(`Contact Info`, "#5429 14111 N Prasada Gateway Ave", "#5429, 14111 N Prasada Gateway Ave") %>%
           str_replace_all("Whitestone Blvd Cedar Park", "#Whitestone Blvd, Cedar Park") %>%
           str_replace("17, Eastanollee, GA, 30538", "17, Eastanollee, GA, 30538,") %>%
           str_replace("I-55/, I-72", "I-55/I-72") %>%
           str_replace("1A1 (604) 820-0048", "1A1, (604) 820-0048") %>%
           str_replace("#5631, 2480 Whipple Rd, I-880 Exit 24, Hayward, CA, 94544", "#5631, 2480 Whipple Rd, I-880 Exit 24, Hayward, CA, 94544, 99999999999"))

state_info <- tibble(strstate = state.abb, 
                     region = factor(state.region, 
                                     levels = c("South", "North Central", "West", "Northeast"),
                                     labels = c("South", "Midwest", "West", "Northern")),
                     statename = state.name) 

dat <- dat %>% 
  rename_all(tolower) %>%
  mutate(opendate = mdy(opendate), date_super = mdy(date_super), 
         strstate_order = fct_reorder(strstate, opendate, fun = min, .desc = TRUE) ) %>%
  left_join(state_info) %>%
  mutate(zipcode2 = case_when(streetaddr == "2750 E. Germann Road" ~ 85286,
                              streetaddr == "3301 North Tower Road" ~ 80011,
                              streetaddr == "1100 N. Estrella Parkway" ~ 85338),
         zipcode2 = ifelse(is.na(zipcode2), zipcode, zipcode2)) %>%
  select(-zipcode) %>%
  rename(zipcode = zipcode2)

locs1 <- locs %>%
  separate(`Contact Info`, c("number", "streetaddr", "strcity", "strstate", "zipcode", "phone-number", "other"), ",")

locs_exit <- locs1 %>%
  filter(strcity %>% str_detect( "Exit|exit|Exiit|Exiyt|xit")) %>%
  mutate(strcity = strstate, strstate = zipcode, zipcode = `phone-number`, `phone-number` = other, other = "") %>%
  select(-other)

locs_good <- locs1 %>%
  filter(other %in% c("", "(NOP)", " (NOP)") | is.na(other), !str_detect(strcity, "Exit")) %>%
  select(-other)


# street address and city need to be put together then move other columns
locs_mess <- locs1 %>%
  filter(str_length(`phone-number`) <= 6 ) %>% 
  mutate(streetaddr = str_c(streetaddr, " ", strcity), strcity = zipcode, strstate = `phone-number`, zipcode = other, `phone-number` = NA) %>%
  select(-other)

# Should be empty  
locs1 %>%
  filter(!`Store Name` %in% c(locs_exit$`Store Name`, locs_good$`Store Name`, locs_mess$`Store Name`)) 

locs <- locs_good %>%
  bind_rows(locs_exit) %>%
  bind_rows(locs_mess) %>%
  select(-`Zip Codes`, - Location) %>%
  mutate_all(.funs = "str_trim") %>%
  filter(str_count(zipcode) < 7, !str_detect(`Store Name`, "Sam's")) 

#### Only use the key where there is one walmart

locs_dup <- unique(locs$zipcode[duplicated(locs$zipcode)])
dat_dup <- unique(dat$zipcode[duplicated(dat$zipcode)])

locs_merge <- locs %>%
  filter(!zipcode %in% locs_dup)

dat_merge <- dat %>%
  filter(!zipcode %in% dat_dup) %>%
  mutate(zipcode = parse_character(zipcode))

similarity <- stringdist::stringdistmatrix(with(dat, str_c(streetaddr, strcity, strstate, zipcode)) , with(locs, str_c(streetaddr, strcity, strstate, zipcode)))
simzip   <- stringdist::stringdistmatrix(as.character(dat$zipcode),as.character(locs$zipcode))


datkey <- tibble(rank = apply(similarity, 1, min), locs_key = apply(similarity, 1, which.min), dat_order = 1:nrow(similarity))

zips_match <- map2(datkey[["dat_order"]], datkey[["locs_key"]], ~ simzip[.x,.y]) %>% unlist()

datkey <- datkey %>%
  mutate(zip_match = zips_match) %>%
  filter(zip_match == 0 |  rank < 20 & zip_match <= 2 | rank < 10  & zip_match <= 4)

fuzzy_merge <- function(x_row, y_row, x_dat, y_dat){
  bind_cols(x_dat[x_row, ], y_dat[y_row, ])
}

mdat <- map2(datkey[["dat_order"]], datkey[["locs_key"]], ~ fuzzy_merge(.x, .y, x_dat = dat, y_dat = locs)) %>%
  bind_rows()

dat_nomerge <- dat %>%
  filter(!streetaddr %in% mdat$streetaddr)

locs_nomerge <- locs %>%
  filter(!streetaddr %in% mdat$streetaddr1)

write_csv(mdat, path = "walmart_timeloc.csv")
write_csv(dat_nomerge, path = "walmart_time_nomerge.csv")
write_csv(locs_nomerge, path = "walmart_loc_nomerge.csv")


